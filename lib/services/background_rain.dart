import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather.dart';
import '../utils/share_text.dart';
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

const _morningChannel = AndroidNotificationChannel(
  'morning_summary',
  'Morning summary',
  description: "The day's forecast each morning",
  importance: Importance.defaultImportance,
);

Future<void> _maybeMorningSummary(
  SharedPreferences prefs,
  FlutterLocalNotificationsPlugin plugin,
  AndroidFlutterLocalNotificationsPlugin? android,
  Place place,
  Map<String, WeatherData> fetched,
) async {
  if (!(prefs.getBool('morningSummary') ?? false)) return;
  final lastMs = prefs.getInt('morningSummaryMs');
  final last = lastMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastMs);
  if (!morningSummaryDue(DateTime.now(), last)) return;
  final d = fetched[place.key];
  if (d == null) return; // fetch failed; the next run (30 min) retries
  final imperial = prefs.getBool('imperial') ?? true;
  String fmt(double c) => '${(imperial ? c * 9 / 5 + 32 : c).round()}°';
  final m = morningSummary(place.name, d, fmt);
  await android?.createNotificationChannel(_morningChannel);
  await plugin.show(
    'morning'.hashCode,
    m.title,
    m.body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        'morning_summary',
        'Morning summary',
        styleInformation: BigTextStyleInformation(m.body),
      ),
    ),
  );
  await prefs.setInt('morningSummaryMs', DateTime.now().millisecondsSinceEpoch);
}

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

  final svc = WeatherService();
  // Fetched forecasts, reused below so the first place isn't requested twice.
  final fetched = <String, WeatherData>{};

  // Keep the home screen widget fresh from the background too.
  try {
    final first = places.first;
    final wd = await svc.fetch(first);
    fetched[first.key] = wd;
    final imp = prefs.getBool('imperial') ?? true;
    await updateAtmosWidget(wd, first.name, imp);
  } catch (_) {}

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  final android = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await android?.createNotificationChannel(_channel);

  // Morning summary (opt-in): once a day, first run after 7 AM.
  await _maybeMorningSummary(prefs, plugin, android, places.first, fetched);

  // One notification per 6 hours so a passing shower doesn't spam.
  final lastNotify = prefs.getInt('lastRainNotifyMs') ?? 0;
  if (DateTime.now().millisecondsSinceEpoch - lastNotify <
      const Duration(hours: 6).inMilliseconds) {
    return;
  }

  for (final p in places.take(3)) {
    WeatherData d;
    try {
      d = fetched[p.key] ?? await svc.fetch(p);
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
      'lastRainNotifyMs',
      DateTime.now().millisecondsSinceEpoch,
    );
    break;
  }
}
