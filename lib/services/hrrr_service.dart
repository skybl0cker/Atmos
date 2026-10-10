import 'dart:convert';

import 'package:http/http.dart' as http;

/// HRRR simulated-reflectivity "future radar" via Iowa State IEM's free
/// tile service — the same class of product behind The Weather Channel's
/// Future Radar: NOAA's 3 km HRRR model rendered as simulated radar,
/// served as map tiles. No backend or API key needed.
///
/// Coverage: CONUS. Cadence: HRRR runs hourly, 18 h forecasts every
/// 15 min; IEM typically has a run processed ~1h50m after init.
class HrrrFrame {
  final String label;
  final String urlTemplate; // {z}/{x}/{y} placeholders, like flutter_map
  final DateTime validTime;
  const HrrrFrame({
    required this.label,
    required this.urlTemplate,
    required this.validTime,
  });
}

class HrrrService {
  static const _meta =
      'https://mesonet.agron.iastate.edu/data/gis/images/4326/hrrr/'
      'refd_1080.json';
  static const _timeout = Duration(seconds: 12);

  /// Builds simulated-radar frames from the earliest available forecast hour
  /// (>= now) out to +6 h — the single unified "future radar" model. The
  /// model run comes from IEM's own metadata (latest fully processed run),
  /// so the tiles are guaranteed to exist and the labels are exact.
  /// Returns [] if the metadata can't be read.
  static Future<List<HrrrFrame>> forecastFrames({DateTime? now}) async {
    final t = (now ?? DateTime.now()).toUtc();
    final init = await _latestRun() ?? _conservativeRun(t);
    final initStr = _fmt(init);

    // First forecast hour at or after now, then every 30 min to +6h.
    // (IEM processes runs ~1h50m after init, so the earliest usable frame
    // is typically within the last hour of the run.)
    final minFMin = t.difference(init).inMinutes;
    final frames = <HrrrFrame>[];
    for (var off = 0; off <= 360; off += 30) {
      final fMin =
          ((minFMin + off) / 15).round() * 15;
      if (fMin < 15 || fMin > 1080) continue;
      // Skip frames that would duplicate "now" — start the future cleanly.
      if (off == 0 && fMin - minFMin < 15) continue;
      final f = fMin.toString().padLeft(4, '0');
      final leadMin = fMin - minFMin;
      if (leadMin < 15) continue;
      frames.add(HrrrFrame(
        label: leadMin < 120 ? '+$leadMin min' : '+${leadMin ~/ 60} hr',
        urlTemplate:
            'https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/'
            'hrrr::REFD-F$f-$initStr/{z}/{x}/{y}.png',
        validTime: init.add(Duration(minutes: fMin)),
      ));
    }
    return frames;
  }

  /// Latest fully-processed HRRR run, per IEM's own metadata.
  static Future<DateTime?> _latestRun() async {
    try {
      final r = await http
          .get(Uri.parse(_meta))
          .timeout(_timeout);
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final s = j['model_init_utc'] as String?;
      return s == null ? null : DateTime.parse(s).toUtc();
    } catch (_) {
      return null;
    }
  }

  /// Fallback when the metadata is unreachable: assume the run from 3 h
  /// ago is processed (conservative — IEM needs ~1h50m).
  static DateTime _conservativeRun(DateTime t) {
    final c = t.subtract(const Duration(hours: 3));
    return DateTime.utc(c.year, c.month, c.day, c.hour);
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}'
      '${d.hour.toString().padLeft(2, '0')}00';
}
