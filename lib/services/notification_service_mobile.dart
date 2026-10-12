import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alert.dart';

class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _ready = true;
  }

  /// Asks the OS for notification permission. Kept separate from [init] so
  /// the app can sequence its permission dialogs: Android shows only one
  /// system permission dialog at a time, and firing the notification
  /// request at startup raced the location request and silently dropped
  /// the location prompt. The app now asks for location first (fresh
  /// installs), then notifications once that dialog is answered.
  Future<void> requestPermission() async {
    await init(); // no-op if already initialized
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> showAlert(WeatherAlert a) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'weather_alerts',
        'Weather alerts',
        channelDescription: 'Active NWS watches and warnings for your places',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(a.id.hashCode, a.event,
        a.headline.isNotEmpty ? a.headline : a.areas, details);
  }
}
