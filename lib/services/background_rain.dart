import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather.dart';
import 'weather_service.dart';
import 'widget_service.dart';

/// Entry point for the Android background worker. Fires roughly every 30
/// minutes even when the app is closed and notifies when rain is about to
/// start at one of Sir's places. Also refreshes the home screen widget.
///
/// iOS cannot do this without a push server (background execution is too
/// restricted), and the web build has no background execution at all — this
/// is Android-only by platform reality, not by choice.
///
/// The Workmanager entry point lives in background_dispatcher.dart
/// (atmosDispatcher), which routes here or to runAlertCheck().

const _channel = AndroidNotificationChannel(
  'rain_nowcast',
  'Rain alerts',
  description: 'Notifies when rain is about to start',
  importance: Importance.high,
);

Future<void> runRainCheck() async {
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool('notifications') ?? true)) return;

  final places = <Place>[];
  final last = prefs.getString('last');
  if (last != null) {
    places.add(Place.fromJson(jsonDecode(last) as Map<String, dynamic>));
  }
  final saved = prefs.getString('saved');
  if (saved != null) {
    for (final e in (jsonDecode(saved) as List).take(3)) {
      final p = Place.fromJson(e as Map<String, dynamic>);
      if (places.every((q) => q.key != p.key)) places.add(p);
    }
  }
  if (places.isEmpty) return;

  // Keep the home screen widget fresh from the background too.
  try {
    final first = places.first;
    final wd = await WeatherService().fetch(first);
    final imp = prefs.getBool('imperial') ?? true;
    await updateAtmosWidget(wd, first.name, imp);
  } catch (_) {}

  // One notification per 6 hours so a passing shower doesn't spam.
  final lastNotify = prefs.getInt('lastRainNotifyMs') ?? 0;
  if (DateTime.now().millisecondsSinceEpoch - lastNotify <
      const Duration(hours: 6).inMilliseconds) {
    return;
  }

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  ));
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);

  final svc = WeatherService();
  for (final p in places.take(3)) {
    WeatherData d;
    try {
      d = await svc.fetch(p);
    } catch (_) {
      continue;
    }
    final startIn = d.rainStartsIn;
    if (startIn == null || startIn > const Duration(minutes: 60)) continue;

    final when = startIn.inMinutes <= 1
        ? 'starting now'
        : 'starting in ~${startIn.inMinutes} min';
    await plugin.show(
      p.key.hashCode,
      'Rain $when',
      'Precipitation is on the way near ${p.name}.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'rain_nowcast',
          'Rain alerts',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
    await prefs.setInt(
        'lastRainNotifyMs', DateTime.now().millisecondsSinceEpoch);
    break;
  }
}
