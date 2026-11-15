import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../models/weather.dart';
import 'weather_codes.dart';

/// A short, human sentence or two about what's coming — the line under the
/// big temperature ("Rain likely around 7 PM. Cooler tomorrow.").
String weatherSummary(WeatherData d, String Function(double c) fmtTemp) {
  final c = d.current;
  final hours = d.hourly;
  final parts = <String>[];
  String at(DateTime t) => DateFormat('h a').format(t);

  bool wet(HourlyPoint h) => h.precipProb >= 50 || h.precipMm >= 0.3;
  String kindFor(int code) => code >= 95
      ? 'Storms'
      : isSnowCode(code)
      ? 'Snow'
      : 'Rain';
  final wetNow = isRainCode(c.code) || isSnowCode(c.code) || c.code >= 95;

  if (wetNow) {
    final dryIdx = hours.indexWhere(
      (h) => h.precipProb < 30 && h.precipMm < 0.1,
      1,
    );
    parts.add(
      dryIdx > 0 && dryIdx <= 12
          ? '${kindFor(c.code)} easing around ${at(hours[dryIdx].time)}.'
          : '${kindFor(c.code)} continuing for the next several hours.',
    );
  } else {
    final wetIdx = hours.indexWhere(wet, 1);
    if (wetIdx > 0 && wetIdx <= 12) {
      final h = hours[wetIdx];
      parts.add('${kindFor(h.code)} likely around ${at(h.time)}.');
    } else {
      parts.add(c.isDay ? 'Dry for the rest of the day.' : 'Dry overnight.');
    }
  }

  // One more sentence, the most useful of: wind, how today compares with
  // yesterday (what to wear *now* — preferred through mid-afternoon), or
  // what tomorrow brings.
  String? tomorrow;
  if (d.daily.length > 1) {
    final diff = d.daily[1].maxC - d.daily[0].maxC;
    if (diff <= -4) {
      tomorrow = 'Cooler tomorrow, high of ${fmtTemp(d.daily[1].maxC)}.';
    } else if (diff >= 4) {
      tomorrow = 'Warmer tomorrow, high of ${fmtTemp(d.daily[1].maxC)}.';
    }
  }
  final yesterday = yesterdayNote(d);
  final earlyInDay = c.time.hour < 15;

  if (c.windKmh >= 40) {
    parts.add('Windy out there.');
  } else if (earlyInDay && yesterday != null) {
    parts.add(yesterday);
  } else if (tomorrow != null) {
    parts.add(tomorrow);
  } else if (yesterday != null) {
    parts.add(yesterday);
  }
  return parts.join(' ');
}

/// "Warmer than yesterday." — from today's high vs yesterday's. Null when
/// the days are within 3 °C (about 5 °F) or yesterday is unknown.
String? yesterdayNote(WeatherData d) {
  final diff = d.vsYesterdayC;
  if (diff == null || diff.abs() < 3) return null;
  final much = diff.abs() >= 7 ? 'Much ' : '';
  final word = diff > 0 ? 'warmer' : 'cooler';
  final text = '$much$word than yesterday.';
  return text[0].toUpperCase() + text.substring(1);
}

/// Dew point (°C) from temperature and relative humidity (Magnus formula).
double dewPointC(double tempC, double rh) {
  const a = 17.62, b = 243.12;
  final g = (a * tempC) / (b + tempC) + math.log(rh.clamp(1.0, 100.0) / 100);
  return (b * g) / (a - g);
}
