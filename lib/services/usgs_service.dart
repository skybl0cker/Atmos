import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Earthquakes from the USGS Earthquake Hazards Program. Free, no key,
/// CORS-enabled (works on web too).
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
  static const _cacheTtl = Duration(minutes: 15);
  static final Map<String, List<Earthquake>> _cache = {};
  static final Map<String, DateTime> _fetched = {};

  /// Quakes of at least [minMag] within [radiusKm] of a point over the last
  /// [days] days, newest first. Asks USGS for the radius directly, so only
  /// genuinely local events come back. Never throws (empty on failure).
  static Future<List<Earthquake>> nearby(
    double lat,
    double lon, {
    double radiusKm = 483,
    double minMag = 5.0,
    int days = 7,
  }) async {
    final key =
        '${lat.toStringAsFixed(1)},${lon.toStringAsFixed(1)},$radiusKm,$minMag';
    final f = _fetched[key];
    if (f != null && DateTime.now().difference(f) < _cacheTtl) {
      return _cache[key]!;
    }
    try {
      final start = DateTime.now().toUtc().subtract(Duration(days: days));
      final uri = Uri.https('earthquake.usgs.gov', '/fdsnws/event/1/query', {
        'format': 'geojson',
        'starttime': start.toIso8601String().substring(0, 10),
        'latitude': lat.toStringAsFixed(4),
        'longitude': lon.toStringAsFixed(4),
        'maxradiuskm': radiusKm.toStringAsFixed(0),
        'minmagnitude': minMag.toStringAsFixed(1),
        'orderby': 'time',
        'limit': '20',
      });
      final r = await http.get(uri).timeout(_timeout);
      if (r.statusCode != 200) return _cache[key] ?? [];
      final quakes = parseGeoJson(r.body);
      _cache[key] = quakes;
      _fetched[key] = DateTime.now();
      return quakes;
    } catch (_) {
      return _cache[key] ?? [];
    }
  }

  @visibleForTesting
  static List<Earthquake> parseGeoJson(String body) {
    final features =
        ((jsonDecode(body) as Map<String, dynamic>)['features'] as List? ??
                const [])
            .cast<Map<String, dynamic>>();
    return [for (final f in features) _parse(f)]
        .whereType<Earthquake>()
        .toList();
  }

  static Earthquake? _parse(Map<String, dynamic> f) {
    try {
      final p = (f['properties'] as Map).cast<String, dynamic>();
      final g = (f['geometry'] as Map).cast<String, dynamic>();
      final coords = (g['coordinates'] as List).cast<num>();
      return Earthquake(
        mag: (p['mag'] as num).toDouble(),
        place: (p['place'] as String?) ?? 'Unknown location',
        time: DateTime.fromMillisecondsSinceEpoch(
          (p['time'] as num).toInt(),
          isUtc: true,
        ),
        location: LatLng(coords[1].toDouble(), coords[0].toDouble()),
        tsunami: (p['tsunami'] as num?)?.toInt() ?? 0,
        url: (p['url'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
