import '../models/alert.dart';

/// Web stub: flutter_local_notifications has no web implementation,
/// so alert notifications are a no-op when running as a web app.
/// In-app alert banners still work; only OS-level push is skipped.
class NotificationService {
  Future<void> init() async {}

  /// Web stub: no OS-level notifications, so this is a no-op.
  Future<void> requestPermission() async {}

  Future<void> showAlert(WeatherAlert a) async {}
}
