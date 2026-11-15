import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/weather.dart';

/// What a typical day looks like at this time of year, from real past
/// weather (Open-Meteo's historical archive, ERA5 reanalysis).
class DayNormal {
  final double highC;
  final double lowC;

  /// How many past days went into the average.
  final int samples;
  const DayNormal({
    required this.highC,
    required this.lowC,
    required this.samples,
  });

  Map<String, dynamic> toJson() => {'h': highC, 'l': lowC, 'n': samples};
  static DayNormal fromJson(Map<String, dynamic> j) => DayNormal(
    highC: (j['h'] as num).toDouble(),
    lowC: (j['l'] as num).toDouble(),
    samples: (j['n'] as num).toInt(),
  );
}

class ClimateService {
  static const _timeout = Duration(seconds: 20);

  /// How many past years, and how many days either side of the date, make
  /// up the "normal". 10 years × 15 days ≈ 150 samples — stable enough
  /// without needing a 30-year record.
  static const years = 10;
  static const window = 7;

  /// The normal high / low for [date] at [p], or null on any failure.
  /// One request: a 10-year daily series (~70 KB), averaged locally.
  static Future<DayNormal?> normalFor(Place p, DateTime date) async {
    try {
      String ymd(DateTime d) => d.toIso8601String().substring(0, 10);
      final start = DateTime(
        date.year - years,
        date.month,
        date.day,
      ).subtract(const Duration(days: window));
      final end = DateTime(
        date.year - 1,
        date.month,
        date.day,
      ).add(const Duration(days: window));
      final uri = Uri.https('archive-api.open-meteo.com', '/v1/archive', {
        'latitude': p.lat.toStringAsFixed(4),
        'longitude': p.lon.toStringAsFixed(4),
        'start_date': ymd(start),
        'end_date': ymd(end),
        'daily': 'temperature_2m_max,temperature_2m_min',
        'timezone': 'auto',
      });
      final r = await http.get(uri).timeout(_timeout);
      if (r.statusCode != 200) return null;
      return computeNormal(r.body, date);
    } catch (_) {
      return null;
    }
  }

  /// Averages the days within [window] calendar days of [date]'s month and
  /// day, in every year of the series. Pure, for tests.
  static DayNormal? computeNormal(String body, DateTime date) {
    final d = (jsonDecode(body) as Map<String, dynamic>)['daily'] as Map?;
    if (d == null) return null;
    final times = (d['time'] as List).cast<String>();
    final highs = d['temperature_2m_max'] as List;
    final lows = d['temperature_2m_min'] as List;
    var hi = 0.0, lo = 0.0, n = 0;
    for (var i = 0; i < times.length; i++) {
      final t = DateTime.parse(times[i]);
      // Distance in days to the same month/day in that year (handles the
      // window crossing New Year by checking the neighbouring years too).
      final gap = [t.year - 1, t.year, t.year + 1]
          .map(
            (y) => t.difference(DateTime(y, date.month, date.day)).inDays.abs(),
          )
          .reduce((a, b) => a < b ? a : b);
      if (gap > window) continue;
      final h = highs[i] as num?, l = lows[i] as num?;
      if (h == null || l == null) continue;
      hi += h.toDouble();
      lo += l.toDouble();
      n++;
    }
    if (n < 10) return null;
    return DayNormal(highC: hi / n, lowC: lo / n, samples: n);
  }
}
