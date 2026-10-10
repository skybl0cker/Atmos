import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather.dart';
import 'alerts_service.dart';

/// Checks NWS for NEW severe/extreme alerts at Sir's places and fires a
/// high-priority notification for each one not seen before.
///
/// Only severe/extreme fire in the background — advisories and watches can
/// wait for the next app open, so a 2 AM wind advisory doesn't wake anyone.

const _channel = AndroidNotificationChannel(
  'severe_alerts',
  'Severe weather alerts',
  description: 'Wakes the phone for severe NWS warnings',
  importance: Importance.max,
);

Future<void> runAlertCheck() async {
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

  final seen = (prefs.getStringList('seenAlerts') ?? []).toSet();
  final service = AlertsService();
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);

  var updated = false;
  for (final place in places) {
    final alerts = await service.active(place.lat, place.lon);
    for (final a in alerts) {
      if (seen.contains(a.id)) continue;
      seen.add(a.id);
      updated = true;
      if (a.isSevere) {
        await plugin.show(
          a.id.hashCode,
          '⚠ ${a.event} — ${place.name}',
          a.headline.isNotEmpty ? a.headline : a.areas,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'severe_alerts',
              'Severe weather alerts',
              channelDescription: 'Wakes the phone for severe NWS warnings',
              importance: Importance.max,
              priority: Priority.max,
            ),
          ),
        );
      }
    }
  }
  if (updated) {
    await prefs.setStringList('seenAlerts', seen.toList());
  }
}
