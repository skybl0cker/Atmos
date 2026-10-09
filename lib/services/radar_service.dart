import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// Precipitation radar from RainViewer (rainviewer.com) — free, no API key,
/// global coverage, sourced from worldwide radar composites. Frames include
/// observed history (~90 min) plus motion-extrapolated nowcast frames when
/// available, so the loop can show the next 30–60 minutes of expected
/// precipitation.
///
/// Docs: https://www.rainviewer.com/api.html
class RadarFrame {
  /// Display label computed at load time (stable during playback).
  final String label;
  final bool isForecast;

  /// True for wind-advected synthetic frames (used when RainViewer's own
  /// nowcast is unavailable). Rendered shifted along the steering wind.
  final bool estimated;
  final int leadMinutes;

  /// Frame time as Unix seconds (from the RainViewer API). Used to derive
  /// the real time delta when measuring echo motion.
  final int timeUtc;
  final String _path;

  const RadarFrame({
    required this.label,
    required this.isForecast,
    required String path,
    required this.timeUtc,
    this.estimated = false,
    this.leadMinutes = 0,
  }) : _path = path;

  /// Universal Blue color scheme, smoothed.
  String get tileUrl =>
      'https://tilecache.rainviewer.com$_path/256/{z}/{x}/{y}/2/1_1.png';

  /// Concrete tile URL covering [lat]/[lon] at [zoom] — for fetching a
  /// single tile to measure echo motion (no map widget involved).
  String tileUrlAt(double lat, double lon, int zoom) {
    final n = math.pow(2, zoom).toInt();
    final x = (((lon + 180) / 360 * n).floor()).clamp(0, n - 1);
    final latRad = lat * math.pi / 180;
    final y =
        (((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
                    2 *
                    n)
                .floor())
            .clamp(0, n - 1);
    return 'https://tilecache.rainviewer.com$_path/256/$zoom/$x/$y/2/1_1.png';
  }

  /// Unique widget key — estimated frames share the anchor's tiles.
  String get key => '$tileUrl|est=$estimated|lead=$leadMinutes';
}

class RadarService {
  static const _api = 'https://api.rainviewer.com/public/weather-maps.json';
  static const _cacheTtl = Duration(minutes: 10);

  static List<RadarFrame>? _cache;
  static DateTime? _fetched;

  /// Returns past frames (oldest first) followed by forecast frames, with the
  /// last past frame marked "Now". Keeps at most 8 past frames so the free
  /// tile server is not hammered.
  static Future<List<RadarFrame>> fetchFrames() async {
    if (_cache != null &&
        _fetched != null &&
        DateTime.now().difference(_fetched!) < _cacheTtl) {
      return _cache!;
    }
    final r = await http
        .get(Uri.parse(_api))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw Exception('Radar service error (${r.statusCode})');
    }
    final radar =
        (jsonDecode(r.body) as Map<String, dynamic>)['radar']
            as Map<String, dynamic>;
    final past =
        (radar['past'] as List).cast<Map<String, dynamic>>();
    final nowcast =
        ((radar['nowcast'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (past.isEmpty) throw Exception('Radar service returned no frames');

    final recent = past.length > 8 ? past.sublist(past.length - 8) : past;
    final anchor = DateTime.fromMillisecondsSinceEpoch(
        (recent.last['time'] as int) * 1000,
        isUtc: true);

    final frames = <RadarFrame>[
      for (final f in recent)
        RadarFrame(
          label: _agoLabel(anchor, f),
          isForecast: false,
          path: f['path'] as String,
          timeUtc: f['time'] as int,
        ),
      for (final f in nowcast)
        RadarFrame(
          label: _futureLabel(anchor, f),
          isForecast: true,
          path: f['path'] as String,
          timeUtc: f['time'] as int,
        ),
    ];
    _cache = frames;
    _fetched = DateTime.now();
    return frames;
  }

  /// When RainViewer's motion-extrapolated nowcast frames are unavailable
  /// (common), synthesize +30/+60 min frames by advecting the latest
  /// observed echo. The renderer shifts them along the measured echo motion
  /// when available, else the layer-mean steering wind. Set [force] to add
  /// the frames even when the model wind is calm — used when measured echo
  /// motion exists despite a weak model wind.
  static List<RadarFrame> addEstimatedForecast(
      List<RadarFrame> frames, double windKmh, int windDir,
      {bool force = false}) {
    if (frames.any((f) => f.isForecast)) return frames;
    if (windKmh < 3 && !force || frames.isEmpty) return frames;
    final anchor = frames.lastWhere((f) => !f.isForecast,
        orElse: () => frames.last);
    return [
      ...frames,
      for (final lead in [30, 60])
        RadarFrame(
          label: '+$lead min',
          isForecast: true,
          estimated: true,
          leadMinutes: lead,
          path: anchor._path,
          timeUtc: anchor.timeUtc + lead * 60,
        ),
    ];
  }

  static String _agoLabel(DateTime anchor, Map<String, dynamic> f) {
    final t = DateTime.fromMillisecondsSinceEpoch((f['time'] as int) * 1000,
        isUtc: true);
    final m = anchor.difference(t).inMinutes;
    if (m <= 2) return 'Now';
    return '$m min ago';
  }

  static String _futureLabel(DateTime anchor, Map<String, dynamic> f) {
    final t = DateTime.fromMillisecondsSinceEpoch((f['time'] as int) * 1000,
        isUtc: true);
    final m = t.difference(anchor).inMinutes;
    return '+$m min';
  }
}
