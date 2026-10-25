import 'package:workmanager/workmanager.dart';
import 'notifications.dart';
import '../features/materials/materials_background.dart';

Future<void> initializePlatform() async {
  await Notifications.init();
  try {
    await Workmanager().initialize(materialsCallbackDispatcher);
    await WorkmanagerMaterialsScheduler().ensurePeriodic();
  } catch (_) {
    // Desktop has no WorkManager. The in-process queue still runs.
  }
}
