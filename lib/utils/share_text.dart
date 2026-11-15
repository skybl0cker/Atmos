import 'package:intl/intl.dart' show DateFormat;

import '../models/weather.dart';
import 'insights.dart';
import 'summary.dart';
import 'tips.dart';
import 'weather_codes.dart';

/// The daily 7 AM notification: once per calendar day (device time), in a
/// 7–11 AM window so a late background run still delivers it that morning.
bool morningSummaryDue(DateTime now, DateTime? lastSent, {int hour = 7}) {
  if (now.hour < hour || now.hour >= hour + 4) return false;
  if (lastSent == null) return true;
  return !(lastSent.year == now.year &&
      lastSent.month == now.month &&
      lastSent.day == now.day);
}

/// Title and body for the morning notification, e.g.
///
///     Good morning — Knoxville: 34°, Clear sky
///     High 47° / low 35°. Dry for the rest of the day. Grab a warm jacket.
({String title, String body}) morningSummary(
  String place,
  WeatherData d,
  String Function(double c) fmtTemp,
) {
  final c = d.current;
  final title =
      'Good morning — $place: ${fmtTemp(c.tempC)}, ${describe(c.code)}';
  final parts = <String>[
    if (d.daily.isNotEmpty)
      'High ${fmtTemp(d.daily.first.maxC)} / low ${fmtTemp(d.daily.first.minC)}.',
    weatherSummary(d, fmtTemp),
  ];
  final tip = dayTips(d, max: 1);
  if (tip.isNotEmpty) parts.add('${tip.first.text}.');
  return (title: title, body: parts.join(' '));
}

/// A plain-text forecast to paste into a message:
///
///     Knoxville — 35°, Clear sky (feels 29°)
///     Today: high 47°, low 35°. Dry overnight.
///     Tomorrow: 53° / 32°, Mainly clear
///     Sunday: 56° / 31°, Partly cloudy, 40% rain
///     Best time outside: tomorrow, 2–4 PM
///     — Atmos
String shareText(
  String place,
  WeatherData d,
  String Function(double c) fmtTemp,
) {
  final c = d.current;
  final lines = <String>[
    '$place — ${fmtTemp(c.tempC)}, ${describe(c.code)} '
        '(feels ${fmtTemp(c.feelsC)})',
  ];
  if (d.daily.isNotEmpty) {
    final t = d.daily.first;
    lines.add(
      'Today: high ${fmtTemp(t.maxC)}, low ${fmtTemp(t.minC)}. '
      '${weatherSummary(d, fmtTemp)}',
    );
  }
  for (final day in d.daily.skip(1).take(2)) {
    final name = identical(day, d.daily[1])
        ? 'Tomorrow'
        : DateFormat('EEEE').format(day.date);
    lines.add(
      '$name: ${fmtTemp(day.maxC)} / ${fmtTemp(day.minC)}, '
      '${describe(day.code)}'
      '${day.precipProb >= 30 ? ', ${day.precipProb}% rain' : ''}',
    );
  }
  final w = bestOutdoorWindow(d);
  if (w != null && w.isGood) {
    final today = DateTime(c.time.year, c.time.month, c.time.day);
    final when = DateTime(w.start.year, w.start.month, w.start.day) == today
        ? 'today'
        : 'tomorrow';
    String h(DateTime x) => DateFormat('h').format(x);
    lines.add(
      'Best time outside: $when, ${h(w.start)}–${h(w.end)} '
      '${DateFormat('a').format(w.end)}',
    );
  }
  lines.add('— Atmos');
  return lines.join('\n');
}
