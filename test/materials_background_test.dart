import 'package:flutter_test/flutter_test.dart';
import 'package:little_graduates/features/materials/materials_background.dart';
import 'package:workmanager/workmanager.dart';

class RecordingWorkmanager extends WorkmanagerPlatform {
  final requests = <OneOffTaskRequest>[];
  final periodic = <PeriodicTaskRequest>[];
  int processing = 0;

  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async {
    requests.add(
      OneOffTaskRequest(
        uniqueName: uniqueName,
        taskName: taskName,
        existingWorkPolicy: existingWorkPolicy,
        constraints: constraints,
        expedited: expedited,
        outOfQuotaPolicy: outOfQuotaPolicy,
        foregroundServiceConfig: foregroundServiceConfig,
        initialDelaySeconds: initialDelay?.inSeconds,
        backoffPolicy: BackoffPolicyConfig(
          backoffPolicy: backoffPolicy,
          backoffDelayMillis: backoffPolicyDelay?.inMilliseconds,
        ),
      ),
    );
  }

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    ForegroundServiceConfig? foregroundServiceConfig,
  }) async {
    periodic.add(
      PeriodicTaskRequest(
        uniqueName: uniqueName,
        taskName: taskName,
        frequencySeconds: frequency?.inSeconds ?? 900,
        existingWorkPolicy: existingWorkPolicy,
        constraints: constraints,
        foregroundServiceConfig: foregroundServiceConfig,
      ),
    );
  }

  @override
  Future<void> registerProcessingTask(
    String uniqueName,
    String taskName, {
    Duration? initialDelay,
    Map<String, dynamic>? inputData,
    Constraints? constraints,
  }) async {
    processing++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Initialize the facade before installing the fake platform.
  Workmanager();
  late WorkmanagerPlatform previous;
  late RecordingWorkmanager recording;
  setUp(() {
    previous = WorkmanagerPlatform.instance;
    recording = RecordingWorkmanager();
    WorkmanagerPlatform.instance = recording;
  });
  tearDown(() => WorkmanagerPlatform.instance = previous);

  for (final api in [31, 36]) {
    test(
      'Android $api requests expedited data-sync without unsafe quota downgrade',
      () async {
        await WorkmanagerMaterialsScheduler(
          isAndroid: true,
          isIOS: false,
          androidApiLevel: () => api,
        ).schedule();
        final request = recording.requests.single;
        expect(request.expedited, isTrue);
        expect(request.outOfQuotaPolicy, OutOfQuotaPolicy.dropWorkRequest);
        expect(request.uniqueName, materialsOneOffTask);
        expect(request.taskName, materialsOneOffTask);
        expect(request.existingWorkPolicy, ExistingWorkPolicy.keep);
        expect(request.constraints!.networkType, NetworkType.connected);
        expect(request.initialDelaySeconds ?? 0, 0);
        expect(request.backoffPolicy!.backoffPolicy, BackoffPolicy.exponential);
        expect(request.backoffPolicy!.backoffDelayMillis, 30000);
        expect(
          request.foregroundServiceConfig!.foregroundServiceType,
          ForegroundServiceType.dataSync,
        );
        expect(
          request.foregroundServiceConfig!.notificationId,
          materialsForegroundNotificationId,
        );
        expect(
          request.foregroundServiceConfig!.notificationTitle,
          'Uploading material checks',
        );
        expect(recording.processing, 0);
      },
    );
  }

  for (final api in [0, 24, 30]) {
    test(
      'Android API $api keeps the compatible pre-31 foreground-worker path',
      () async {
        await WorkmanagerMaterialsScheduler(
          isAndroid: true,
          isIOS: false,
          androidApiLevel: () => api,
        ).schedule();
        final request = recording.requests.single;
        expect(request.expedited, isFalse);
        expect(request.outOfQuotaPolicy, isNull);
        expect(
          request.foregroundServiceConfig!.foregroundServiceType,
          ForegroundServiceType.dataSync,
        );
      },
    );
  }

  test(
    'quota safety net remains connected ordinary periodic work without FGS',
    () async {
      await WorkmanagerMaterialsScheduler(
        isAndroid: true,
        isIOS: false,
      ).ensurePeriodic();
      final request = recording.periodic.single;
      expect(request.uniqueName, materialsRefreshTask);
      expect(request.taskName, materialsRefreshTask);
      expect(request.frequencySeconds, 3600);
      expect(request.existingWorkPolicy, ExistingPeriodicWorkPolicy.keep);
      expect(request.constraints!.networkType, NetworkType.connected);
      expect(request.foregroundServiceConfig, isNull);
    },
  );

  test(
    'iOS keeps processing scheduling and never calls the Android API lookup',
    () async {
      await WorkmanagerMaterialsScheduler(
        isAndroid: false,
        isIOS: true,
        androidApiLevel: () => throw StateError('Android lookup on iOS'),
      ).schedule();
      expect(recording.requests.single.expedited, isFalse);
      expect(recording.requests.single.outOfQuotaPolicy, isNull);
      expect(recording.processing, 1);
    },
  );
}
