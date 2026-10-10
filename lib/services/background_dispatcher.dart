import 'package:workmanager/workmanager.dart';

import 'background_alerts.dart';
import 'background_rain.dart';

/// Single entry point for all Android background work — Workmanager allows
/// exactly one dispatcher. Branches on the task name registered in main.dart:
/// 'rainCheckTask' (rain nowcast + widget refresh) or 'alertCheckTask'
/// (severe NWS alert check).
@pragma('vm:entry-point')
void atmosDispatcher() {
  Workmanager().executeTask((task, _) async {
    try {
      if (task == 'alertCheckTask') {
        await runAlertCheck();
      } else {
        await runRainCheck();
      }
    } catch (_) {
      // Never crash the worker; next run will try again.
    }
    return true;
  });
}
