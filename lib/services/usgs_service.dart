import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Significant earthquakes from the USGS Earthquake Hazards Program.
/// Free, no key.
class Earthquake {
  final double mag;
  final String place;
  final DateTime time;
  final LatLng location;
  final int tsunami; // 1 if tsunami flag set
  final String url;

  const Earthquake({
    required this.mag,
    required this.place,
    required this.time,
    required this.location,
    required this.tsunami,
    required this.url,
  });
}

class UsgsService {
  static const _timeout = Duration(seconds: 15);
  static List<Earthquake>? _cache;
  static DateTime? _fetched;
  static const _cacheTtl = Duration(minutes: 30);

  /// M5.5+ earthquakes from the last 7 days, newest first.
  static Future<List<Earthquake>> significant() async {
    if (_cache != null &&
        _fetched != null &&
        DateTime.now().difference(_fetched!) < _cacheTtl) {
      return _cache!;
    }
    try {
      final quakes = await _fetch();
      _cache = quakes;
      _fetched = DateTime.now();
      return quakes;
    } catch (_) {
      return _cache ?? [];
    }
  }

  static Future<List<Earthquake>> _fetch() async {
    final start =
        DateTime.now().toUtc().subtract(const Duration(days: 7));
    final startStr =
        '${start.year.toString().padLeft(4, '0')}-'
        '${start.month.toString().padLeft(2, '0')}-'
        '${start.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse(
        'https://earthquake.usgs.gov/fdsnws/event/1/query'
        '?format=geojson&starttime=$startStr&minmagnitude=5.5'
        '&orderby=time&limit=20');
    final r = await http.get(uri).timeout(_timeout);
    if (r.statusCode != 200) return [];
    final features =
        ((jsonDecode(r.body) as Map<String, dynamic>)['features']
                as List)
            .cast<Map<String, dynamic>>();
    return [
      for (final f in features)
        _parse(f),
    ].whereType<Earthquake>().toList();
  }

  static Earthquake? _parse(Map<String, dynamic> f) {
    try {
      final p =
          (f['properties'] as Map).cast<String, dynamic>();
      final g =
          (f['geometry'] as Map).cast<String, dynamic>();
      final coords = (g['coordinates'] as List).cast<num>();
      return Earthquake(
        mag: (p['mag'] as num).toDouble(),
        place: (p['place'] as String?) ?? 'Unknown location',
        time: DateTime.fromMillisecondsSinceEpoch(
            (p['time'] as num).toInt(),
            isUtc: true),
        location: LatLng(
            coords[1].toDouble(), coords[0].toDouble()),
        tsunami: (p['tsunami'] as num?)?.toInt() ?? 0,
        url: (p['url'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
