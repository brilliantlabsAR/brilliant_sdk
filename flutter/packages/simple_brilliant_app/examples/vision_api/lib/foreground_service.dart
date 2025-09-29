import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logging/logging.dart';

final _log = Logger("Foreground task");

void initializeForegroundService() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'foreground_service',
      channelName: 'Frame Service',
      channelImportance: NotificationChannelImportance.MIN,
      iconData: null,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: const ForegroundTaskOptions(
      isOnceEvent: true,
    ),
  );
}

Future<void> startForegroundService() async {
  if (!(await FlutterForegroundTask.isRunningService)) {
    FlutterForegroundTask.startService(
      notificationTitle: 'Frame is connected',
      notificationText: 'Tap to return to the app',
      callback: _startForegroundCallback,
    );
  }
}

@pragma('vm:entry-point')
void _startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_ForegroundFirstTaskHandler());
}

class _ForegroundFirstTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) async {
    _log.info("Starting foreground task");
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    _log.info("Foreground repeat event triggered");
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) async {
    _log.info("Destroying foreground task");
    FlutterForegroundTask.stopService();
  }
}
