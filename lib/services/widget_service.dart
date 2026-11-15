import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather.dart';
import '../utils/summary.dart';
import '../utils/weather_codes.dart';
import '../widgets/scene.dart';

const _channel = MethodChannel('com.skybl0cker.atmos/widget');

/// Saves the forecast for the Android home-screen widget and asks it to
/// redraw. The payload goes through shared_preferences ("widget_payload",
/// read natively by AtmosWidgetProvider) so the background worker can
/// refresh it too: its isolate has no MainActivity to take the channel
/// call, and the widget picks the new data up on its next 30-minute redraw.
Future<void> updateAtmosWidget(
  WeatherData data,
  String placeName,
  bool imperial,
) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'widget_payload',
      jsonEncode(widgetPayload(data, placeName, imperial)),
    );
    await _channel.invokeMethod('updateWidget');
  } catch (_) {
    // No widget placed, or no activity (background); never break the app.
  }
}

/// Opens the native widget style picker (restyles every placed widget).
Future<void> openWidgetStyles() async {
  try {
    await _channel.invokeMethod('openWidgetStyles');
  } catch (_) {}
}

/// Everything the widget layouts show, as strings (the native side stores a
/// `Map<String, String>`). Lists go as JSON. Pure, so it's testable.
Map<String, String> widgetPayload(
  WeatherData data,
  String placeName,
  bool imperial,
) {
  String t(double c) => '${(imperial ? c * 9 / 5 + 32 : c).round()}°';
  final c = data.current;
  final today = data.daily.isNotEmpty ? data.daily.first : null;
  final asset = sceneAsset(data);
  final golden = data.isGoldenHour();
  final scene = asset.endsWith('bg_night.webp')
      ? 'night'
      : asset.endsWith('bg_rain.webp')
      ? 'rain'
      : 'day';
  final tint = sceneTint(asset, golden: golden).toARGB32();

  final hours = [
    for (final (i, h) in data.hourly.take(5).indexed)
      {
        't': i == 0 ? 'Now' : DateFormat('h a').format(h.time),
        'i': widgetIconKey(h.code, i == 0 ? c.isDay : data.isDaylight(h.time)),
        'v': t(i == 0 ? c.tempC : h.tempC),
      },
  ];
  final days = [
    for (final (i, d) in data.daily.take(5).indexed)
      {
        'd': i == 0 ? 'Today' : DateFormat('EEE').format(d.date),
        'i': widgetIconKey(d.code, true),
        'h': t(d.maxC),
        'l': t(d.minC),
        'p': d.precipProb >= 20 ? '${d.precipProb}%' : '',
      },
  ];

  return {
    'place': placeName,
    'temp': t(c.tempC),
    'condition': conditionPhrase(c.code, c.isDay),
    'hilo': today == null ? '' : 'H ${t(today.maxC)}  L ${t(today.minC)}',
    'feels': 'Feels ${t(c.feelsC)}',
    'summary': weatherSummary(data, t),
    'scene': scene,
    'tint': '#${tint.toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'icon': widgetIconKey(c.code, c.isDay),
    'updated': DateFormat('h:mm a').format(c.time),
    'hours': jsonEncode(hours),
    'days': jsonEncode(days),
  };
}

/// Which drawn icon the widget uses (mirrors the app's ArtIcon kinds).
/// Must match the `ic_wx_*` drawables on the Android side.
String widgetIconKey(int code, bool day) {
  if (code == 0 || code == 1) return day ? 'sun' : 'moon';
  if (code == 2) return day ? 'partly_day' : 'partly_night';
  if (code == 45 || code == 48) return 'fog';
  if (code >= 95) return 'storm';
  if (isSnowCode(code)) return 'snow';
  if (isRainCode(code)) return 'rain';
  return 'cloud';
}
