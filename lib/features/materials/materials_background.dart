import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import 'image_codec.dart';
import 'materials_api.dart';
import 'materials_platform.dart';
import 'materials_queue.dart';
import 'materials_sqlite.dart';

const materialsOneOffTask = 'materials-upload';
const materialsProcessingTask = 'in.thelittlegraduates.app.materials';
const materialsRefreshTask = 'in.thelittlegraduates.app.materials.refresh';

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
    } catch (_) {
      return false;
    }
  });
}

Future<bool> drainMaterialsInBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await SqliteMaterialsStore.open();
  final token = await store.getMeta('token');
  if (token == null || token.isEmpty) return false;
  final docs = await getApplicationDocumentsDirectory();
  final api = ApiClient()..token = token;
  final queue = MaterialsQueue(
    store: store,
    root: Directory('${docs.path}/materials_outbox'),
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
  final pendingDevice = (await store.all()).any((item) {
    return item.kind == OutboxKind.media &&
        item.mediaKind == 'video' &&
        item.uploadPath == null &&
        item.status == OutboxStatus.pending;
  });
  if (pendingDevice && !outcome.retry) return false;
  return outcome.retry;
}

class WorkmanagerMaterialsScheduler implements UploadScheduler {
  @override
  Future<void> schedule() async {
    try {
      await Workmanager().registerOneOffTask(
        materialsOneOffTask,
        materialsOneOffTask,
        existingWorkPolicy: ExistingWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 30),
        foregroundServiceConfig: ForegroundServiceConfig(
          notificationTitle: 'Uploading material checks',
          notificationText: 'Photos and videos are being sent to the school',
          foregroundServiceType: ForegroundServiceType.dataSync,
        ),
      );
    } catch (_) {
      // The in-process queue still runs. The next launch schedules again.
    }
    if (!Platform.isIOS) return;
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
