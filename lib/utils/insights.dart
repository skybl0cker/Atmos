import 'dart:math' as math;

import '../models/weather.dart';

// ---------------------------------------------------------------------------
// Best time to be outside
// ---------------------------------------------------------------------------

/// What spoils an hour outdoors the most.
enum OutdoorSnag { rain, cold, heat, wind, sun }

class OutdoorWindow {
  /// First hour of the window (place-local).
  final DateTime start;
  final int hours;

  /// 0–100: 100 is dry, mild, calm daylight.
  final int score;

  /// Average "feels like" over the window (°C).
  final double feelsC;

  /// Highest rain chance in the window (%).
  final int rainChance;

  /// The biggest drawback, when the window still isn't great.
  final OutdoorSnag? snag;

  const OutdoorWindow({
    required this.start,
    required this.hours,
    required this.score,
    required this.feelsC,
    required this.rainChance,
    this.snag,
  });

  DateTime get end => start.add(Duration(hours: hours));
  bool get isGood => score >= 60;
}

/// Penalty points for one forecast hour, and which snag dominated.
(double, OutdoorSnag?) _hourPenalty(HourlyPoint h) {
  final feels = h.feelsC ?? h.tempC;
  final p = <OutdoorSnag, double>{
    OutdoorSnag.rain: h.precipProb * 0.9 + h.precipMm * 12,
    // Comfortable band roughly 15–25 °C feels-like.
    OutdoorSnag.cold: feels < 15 ? (15 - feels) * 3.5 : 0,
    OutdoorSnag.heat: feels > 25 ? (feels - 25) * 4.5 : 0,
    OutdoorSnag.wind: math.max(0, (h.windKmh ?? 0) - 22) * 1.4,
    OutdoorSnag.sun: math.max(0, (h.uv ?? 0) - 7) * 5,
  };
  final total = p.values.fold<double>(0, (a, b) => a + b);
  final worst = p.entries.reduce((a, b) => a.value >= b.value ? a : b);
  return (total, worst.value >= 8 ? worst.key : null);
}

/// The best [length]-hour stretch of daylight in the next [lookAhead]
/// hours, judged on rain, feels-like, wind and UV. Null when there aren't
/// [length] daylight hours in a row left in that span.
OutdoorWindow? bestOutdoorWindow(
  WeatherData d, {
  int length = 2,
  int lookAhead = 24,
}) {
  final hours = d.hourly.take(lookAhead).toList();
  OutdoorWindow? best;
  for (var i = 0; i + length <= hours.length; i++) {
    final slice = hours.sublist(i, i + length);
    // Daylight only (the current hour counts if it's day right now).
    final allDay = slice.every(
      (h) => identical(h, hours.first) ? d.current.isDay : d.isDaylight(h.time),
    );
    if (!allDay) continue;
    var penalty = 0.0;
    final snags = <OutdoorSnag, int>{};
    for (final h in slice) {
      final (p, s) = _hourPenalty(h);
      penalty += p;
      if (s != null) snags[s] = (snags[s] ?? 0) + 1;
    }
    final score = (100 - penalty / length).clamp(0, 100).round();
    if (best != null && score <= best.score) continue;
    best = OutdoorWindow(
      start: slice.first.time,
      hours: length,
      score: score,
      feelsC:
          slice.map((h) => h.feelsC ?? h.tempC).reduce((a, b) => a + b) /
          length,
      rainChance: slice.map((h) => h.precipProb).reduce(math.max),
      snag: snags.isEmpty
          ? null
          : snags.entries.reduce((a, b) => a.value >= b.value ? a : b).key,
    );
  }
  return best;
}

// ---------------------------------------------------------------------------
// This week at a glance
// ---------------------------------------------------------------------------

enum HighlightKind { warmest, coldest, wettest, snowiest, windiest }

class WeekHighlight {
  final HighlightKind kind;
  final DailyPoint day;
  const WeekHighlight(this.kind, this.day);
}

/// Standout days in the next week: warmest afternoon, coldest night, and —
/// only when they're notable — the wettest (≥ 50% chance) and windiest
/// (gusts ≥ 50 km/h) days.
List<WeekHighlight> weekHighlights(WeatherData d, {int days = 7}) {
  final week = d.daily.take(days).toList();
  if (week.length < 2) return const [];
  DailyPoint pick(double Function(DailyPoint) by, {bool max = true}) =>
      week.reduce((a, b) => (max ? by(a) >= by(b) : by(a) <= by(b)) ? a : b);

  final out = <WeekHighlight>[
    WeekHighlight(HighlightKind.warmest, pick((p) => p.maxC)),
    WeekHighlight(HighlightKind.coldest, pick((p) => p.minC, max: false)),
  ];
  // Snow (≥ 1 cm) is the bigger story when it's coming.
  final snowy = pick((p) => p.snowCm ?? 0);
  if ((snowy.snowCm ?? 0) >= 1) {
    out.add(WeekHighlight(HighlightKind.snowiest, snowy));
  }
  final wet = pick((p) => p.precipProb + (p.precipMm ?? 0));
  if (wet.precipProb >= 50) out.add(WeekHighlight(HighlightKind.wettest, wet));
  final windy = pick((p) => p.gustMaxKmh ?? p.windMaxKmh ?? 0);
  if ((windy.gustMaxKmh ?? windy.windMaxKmh ?? 0) >= 50) {
    out.add(WeekHighlight(HighlightKind.windiest, windy));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Sun & daylight
// ---------------------------------------------------------------------------

/// Today's daylight compared with yesterday's (positive = longer today).
/// Null when yesterday isn't in the forecast.
Duration? daylightChange(WeatherData d) {
  final y = d.yesterday;
  if (y == null || d.daily.isEmpty) return null;
  return d.daily.first.daylight - y.daylight;
}

/// "2 min 31 s longer than yesterday" / "about the same as yesterday".
String daylightChangeText(Duration change) {
  final s = change.inSeconds.abs();
  if (s < 30) return 'About the same as yesterday';
  final m = s ~/ 60, sec = s % 60;
  final amount = m == 0
      ? '$sec s'
      : sec == 0
      ? '$m min'
      : '$m min $sec s';
  return '$amount ${change.isNegative ? 'shorter' : 'longer'} than yesterday';
}

/// Where the sun is in today's arc: 0 at sunrise → 1 at sunset; null at
/// night.
double? sunProgress(WeatherData d) {
  if (d.daily.isEmpty) return null;
  final t = d.daily.first, now = d.current.time;
  if (now.isBefore(t.sunrise) || !now.isBefore(t.sunset)) return null;
  return now.difference(t.sunrise).inSeconds / t.daylight.inSeconds;
}

/// The next sunrise or sunset after the forecast's "now".
({DateTime time, bool isSunrise})? nextSunEvent(WeatherData d) {
  final now = d.current.time;
  for (final day in d.daily.take(3)) {
    if (day.sunrise.isAfter(now)) return (time: day.sunrise, isSunrise: true);
    if (day.sunset.isAfter(now)) return (time: day.sunset, isSunrise: false);
  }
  return null;
}

/// "2h 05m" / "45m".
String shortDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h == 0 ? '${m}m' : '${h}h ${m.toString().padLeft(2, '0')}m';
}

// ---------------------------------------------------------------------------
// Storm potential, rain totals, UV window
// ---------------------------------------------------------------------------

class StormRisk {
  /// First hour storms look possible.
  final DateTime time;

  /// True for very unstable air (CAPE ≥ 2500 J/kg) — strong storms.
  final bool strong;
  const StormRisk(this.time, {required this.strong});
}

/// The first hour in the next [hours] where thunderstorms look possible:
/// a thunderstorm code, or unstable air (CAPE ≥ 1000 J/kg) together with a
/// real chance of rain (≥ 30%). Instability alone doesn't make storms; it
/// needs something to set it off, which the rain chance stands in for.
StormRisk? stormRisk(WeatherData d, {int hours = 12}) {
  for (final h in d.hourly.take(hours)) {
    final cape = h.cape ?? 0;
    final unstable = cape >= 1000 && h.precipProb >= 30;
    if (h.code >= 95 || unstable) {
      return StormRisk(h.time, strong: cape >= 2500);
    }
  }
  return null;
}

/// Total precipitation expected over the next [hours] (mm).
double rainTotalMm(WeatherData d, {int hours = 24}) =>
    d.hourly.take(hours).fold<double>(0, (a, h) => a + h.precipMm);

/// The stretch of the next [hours] when the UV index is at or above
/// [threshold] (6 = "high"), with its peak. Null when it never gets there
/// or hourly UV isn't in the forecast.
({DateTime start, DateTime end, double peak})? uvWindow(
  WeatherData d, {
  double threshold = 6,
  int hours = 14,
}) {
  DateTime? start, end;
  var peak = 0.0;
  for (final h in d.hourly.take(hours)) {
    final uv = h.uv;
    if (uv == null) continue;
    if (uv >= threshold) {
      start ??= h.time;
      end = h.time.add(const Duration(hours: 1));
      if (uv > peak) peak = uv;
    } else if (start != null) {
      break; // first contiguous stretch only
    }
  }
  if (start == null || end == null) return null;
  return (start: start, end: end, peak: peak);
}

// ---------------------------------------------------------------------------
// Pressure trend
// ---------------------------------------------------------------------------

enum PressureTrend { rising, steady, falling }

/// Forecast change in sea-level pressure over the next [hours] (default
/// 3 h, the standard tendency window). Null when hourly pressure is
/// missing (older cached forecasts).
PressureTrend? pressureTrend(WeatherData d, {int hours = 3}) {
  if (d.hourly.length <= hours) return null;
  final a = d.hourly.first.pressure, b = d.hourly[hours].pressure;
  if (a == null || b == null) return null;
  final delta = b - a;
  if (delta <= -1.5) return PressureTrend.falling;
  if (delta >= 1.5) return PressureTrend.rising;
  return PressureTrend.steady;
}
