import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/notifications.dart';
import 'image_codec.dart';
import 'materials_api.dart';
import 'materials_platform.dart';
import 'materials_queue.dart';
import 'materials_sqlite.dart';

const materialsOneOffTask = 'materials-upload';
const materialsProcessingTask = 'in.thelittlegraduates.app.materials';
const materialsRefreshTask = 'in.thelittlegraduates.app.materials.refresh';

/// Non-zero: WorkManager's default id 0 is posted and cancelled before the
/// shade can show it when the worker exits immediately.
const materialsForegroundNotificationId = 71041;

/// Log line safe for logcat. Bearer tokens are stripped.
String materialsFailureReason(Object error) {
  final text = '$error'.replaceAll(RegExp(r'Bearer\s+\S+'), 'Bearer [redacted]');
  return text.length <= 300 ? text : text.substring(0, 300);
}

/// Android WorkManager and iOS BGTask entry. The isolate is new, so the
/// token and the queue live in sqlite, not in the widget tree.
@pragma('vm:entry-point')
void materialsCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != materialsOneOffTask &&
        taskName != materialsProcessingTask &&
        taskName != materialsRefreshTask &&
        taskName != Workmanager.iOSBackgroundTask) {
      return true;
    }
    try {
      final retry = await drainMaterialsInBackground();
      return !retry;
    } catch (error) {
      debugPrint('materials upload failed ($taskName): ${materialsFailureReason(error)}');
      return false;
    }
  });
}

Future<bool> drainMaterialsInBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  final registry = await SqliteMaterialsStore.open();
  final userId = int.tryParse(await registry.getMeta('active_user') ?? '');
  if (userId == null) return false;
  final store = await SqliteMaterialsStore.open(userId: userId);
  final token = await store.getMeta('token');
  if (token == null || token.isEmpty) return false;
  final docs = await getApplicationDocumentsDirectory();
  final api = ApiClient()..token = token;
  final queue = MaterialsQueue(
    store: store,
    root: Directory('${docs.path}/materials_outbox/$userId'),
    transport: ApiMaterialsTransport(MaterialsApi(api), baseUrl: AppConfig.baseUrl, token: () => token),
    bridge: ChannelMaterialsBridge(),
    scheduler: const NoopScheduler(),
    compressPhotoBytes: (bytes) async => compressMaterialsPhoto(bytes is Uint8List ? bytes : Uint8List.fromList(bytes)),
    // The Android worker has no Activity, so video transcode waits for the
    // next time the app is open. iOS registers this channel on the background
    // engine, and file bytes go out through a background URLSession.
    uploadLimitBytes: () => 40 * 1024 * 1024,
  );
  // The Android worker has no method channel, so video transcode throws
  // NeedsDeviceCompressor and the clip stays pending until the app is open.
  // Photos still compress in Dart. Already-compressed files upload here.
  final outcome = await queue.drain();
  if (outcome.retry) {
    final reasons = [
      for (final item in await store.all())
        if (item.open && (item.lastError != null || item.errorCode != null))
          '${item.kind.name} ${item.errorCode ?? 'retry'}: ${item.lastError ?? 'will retry'}',
    ];
    debugPrint(reasons.isEmpty ? 'materials upload will retry' : 'materials upload will retry: ${reasons.join('; ')}');
  }
  final pendingDevice = (await store.all()).any((item) {
    return item.kind == OutboxKind.media &&
        item.mediaKind == 'video' &&
        item.uploadPath == null &&
        item.status == OutboxStatus.pending;
  });
  if (pendingDevice && !outcome.retry) return false;
  return outcome.retry;
}

// Public bionic API since Android 29; older releases have no exported symbol.
// https://android.googlesource.com/platform/bionic/+/main/libc/include/android/api-level.h
int _androidApiLevel() {
  try {
    return DynamicLibrary.open(
      'libc.so',
    ).lookupFunction<Int32 Function(), int Function()>(
      'android_get_device_api_level',
    )();
  } on ArgumentError {
    return 0;
  }
}

class WorkmanagerMaterialsScheduler implements UploadScheduler {
  WorkmanagerMaterialsScheduler({
    bool? isAndroid,
    bool? isIOS,
    int Function()? androidApiLevel,
  }) : _isAndroid = isAndroid ?? Platform.isAndroid,
       _isIOS = isIOS ?? Platform.isIOS,
       _apiLevel = androidApiLevel ?? _androidApiLevel;

  final bool _isAndroid;
  final bool _isIOS;
  final int Function() _apiLevel;

  @override
  Future<void> schedule() async {
    if (_isAndroid) {
      try {
        await Notifications.requestPermission();
      } catch (error) {
        debugPrint(
          'materials notification permission: ${materialsFailureReason(error)}',
        );
      }
    }
    try {
      // BackgroundWorker always calls setForegroundAsync when configured.
      // API 31+ needs an expedited job to start this FGS from the background.
      // Before 31, keep normal work: this plugin has no getForegroundInfoAsync
      // override for WorkManager's older expedited-work implementation.
      final expedited = _isAndroid && _apiLevel() >= 31;
      await Workmanager().registerOneOffTask(
        materialsOneOffTask,
        materialsOneOffTask,
        existingWorkPolicy: ExistingWorkPolicy.keep,
        expedited: expedited,
        // Never downgrade a configured FGS to ordinary background work: it
        // would repeat the denied start. SQLite and periodic work retain/retry
        // the upload if expedited quota is unavailable.
        outOfQuotaPolicy: expedited ? OutOfQuotaPolicy.dropWorkRequest : null,
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 30),
        foregroundServiceConfig: ForegroundServiceConfig(
          notificationTitle: 'Uploading material checks',
          notificationText: 'Photos and videos are being sent to the school',
          notificationId: materialsForegroundNotificationId,
          foregroundServiceType: ForegroundServiceType.dataSync,
        ),
      );
    } catch (_) {
      // The in-process queue still runs. The next launch schedules again.
    }
    if (!_isIOS) return;
    try {
      await Workmanager().registerProcessingTask(
        materialsProcessingTask,
        materialsProcessingTask,
        initialDelay: const Duration(minutes: 1),
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {}
  }

  /// Safety net: iOS decides when a refresh task actually runs.
  Future<void> ensurePeriodic() async {
    try {
      await Workmanager().registerPeriodicTask(
        materialsRefreshTask,
        materialsRefreshTask,
        frequency: const Duration(hours: 1),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {}
  }
}
