import 'package:intl/intl.dart' show DateFormat;

import '../models/weather.dart';

enum ChangeKind { warmer, cooler, wetter, drier }

/// One meaningful revision to the forecast since it was last seen.
class ForecastChange {
  final ChangeKind kind;
  final DateTime day;
  final double before, after; // °C for temperature, % for rain chance

  const ForecastChange(this.kind, this.day, this.before, this.after);

  /// For ranking: degrees count about as much as 10 points of rain chance.
  double get size =>
      (after - before).abs() *
      (kind == ChangeKind.warmer || kind == ChangeKind.cooler ? 10 : 1);
}

/// Compares the daily highs and rain chances for the next [days] days
/// (matched by date) between an older forecast and a newer one, and keeps
/// only changes a person would notice: highs moving 3 °C (~5 °F) or more,
/// and rain chances moving 30 points or more where one side is likely
/// (≥ 50%). Biggest first, at most [max].
List<ForecastChange> forecastChanges(
  WeatherData old,
  WeatherData fresh, {
  int days = 5,
  int max = 3,
}) {
  final before = {for (final d in old.daily) _key(d.date): d};
  final out = <ForecastChange>[];
  for (final d in fresh.daily.take(days)) {
    final o = before[_key(d.date)];
    if (o == null) continue;
    final dt = d.maxC - o.maxC;
    if (dt.abs() >= 3) {
      out.add(
        ForecastChange(
          dt > 0 ? ChangeKind.warmer : ChangeKind.cooler,
          d.date,
          o.maxC,
          d.maxC,
        ),
      );
    }
    final dp = d.precipProb - o.precipProb;
    if (dp.abs() >= 30 && (d.precipProb >= 50 || o.precipProb >= 50)) {
      out.add(
        ForecastChange(
          dp > 0 ? ChangeKind.wetter : ChangeKind.drier,
          d.date,
          o.precipProb.toDouble(),
          d.precipProb.toDouble(),
        ),
      );
    }
  }
  out.sort((a, b) => b.size.compareTo(a.size));
  return out.take(max).toList();
}

String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// "Saturday's rain chance is now 70% (was 20%)."
String describeChange(
  ForecastChange c,
  DateTime today,
  String Function(double c) fmtTemp,
) {
  final t = DateTime(today.year, today.month, today.day);
  final diff = DateTime(
    c.day.year,
    c.day.month,
    c.day.day,
  ).difference(t).inDays;
  final day = diff == 0
      ? 'Today'
      : diff == 1
      ? 'Tomorrow'
      : DateFormat('EEEE').format(c.day);
  return switch (c.kind) {
    ChangeKind.warmer || ChangeKind.cooler =>
      "$day's high is now ${fmtTemp(c.after)} (was ${fmtTemp(c.before)}).",
    ChangeKind.wetter || ChangeKind.drier =>
      "$day's rain chance is now ${c.after.round()}% "
          '(was ${c.before.round()}%).',
  };
}
