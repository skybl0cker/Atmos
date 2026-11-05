import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Live tropical cyclone data from the National Hurricane Center:
/// storm names from the NHC homepage, position/intensity/track from the
/// ATCF best-track (b-deck) files. Free, no key.
class TropicalStorm {
  final String id; // e.g. AL092026
  final String name; // e.g. Isaias
  final String type; // Hurricane, Tropical Storm, ...
  final double lat;
  final double lon;
  final int windKt;
  final int pressureMb;
  final DateTime time;
  final List<LatLng> trail; // recent best-track positions, oldest first
  final double moveDirDeg; // direction of motion, compass degrees
  final double moveKt; // forward speed, knots

  const TropicalStorm({
    required this.id,
    required this.name,
    required this.type,
    required this.lat,
    required this.lon,
    required this.windKt,
    required this.pressureMb,
    required this.time,
    required this.trail,
    required this.moveDirDeg,
    required this.moveKt,
  });

  int get windMph => (windKt * 1.15078).round();
  int get moveMph => (moveKt * 1.15078).round();

  TropicalStorm withTrail(List<LatLng> t) => TropicalStorm(
    id: id,
    name: name,
    type: type,
    lat: lat,
    lon: lon,
    windKt: windKt,
    pressureMb: pressureMb,
    time: time,
    trail: t,
    moveDirDeg: moveDirDeg,
    moveKt: moveKt,
  );

  /// Saffir-Simpson category 1-5, or 0 for tropical storm/depression.
  int get category {
    if (windKt >= 137) return 5;
    if (windKt >= 113) return 4;
    if (windKt >= 96) return 3;
    if (windKt >= 83) return 2;
    if (windKt >= 64) return 1;
    return 0;
  }

  String get categoryLabel => category > 0 ? 'Category $category' : type;

  String get moveCompass {
    const dirs = [
      'N',
      'NNE',
      'NE',
      'ENE',
      'E',
      'ESE',
      'SE',
      'SSE',
      'S',
      'SSW',
      'SW',
      'WSW',
      'W',
      'WNW',
      'NW',
      'NNW',
    ];
    return dirs[((moveDirDeg + 11.25) / 22.5).floor() % 16];
  }
}

class _BdeckFix {
  final DateTime time;
  final double lat;
  final double lon;
  final int windKt;
  final int pressureMb;
  const _BdeckFix(this.time, this.lat, this.lon, this.windKt, this.pressureMb);
}

class TropicalService {
  static const _timeout = Duration(seconds: 15);
  static List<TropicalStorm>? _cache;
  static DateTime? _fetched;
  static const _cacheTtl = Duration(minutes: 30);

  /// Active tropical cyclones worldwide (NHC areas of responsibility).
  static Future<List<TropicalStorm>> activeStorms() async {
    if (_cache != null &&
        _fetched != null &&
        DateTime.now().difference(_fetched!) < _cacheTtl) {
      return _cache!;
    }
    try {
      final storms = await _fetch();
      _cache = storms;
      _fetched = DateTime.now();
      return storms;
    } catch (_) {
      return _cache ?? [];
    }
  }

  static const _ua = {'User-Agent': 'com.skybl0cker.atmos'};

  /// Current storms from NHC's official machine-readable feed
  /// (CurrentStorms.json), then each storm's recent best-track positions
  /// for the map trail. The trail is optional — a storm still shows if its
  /// b-deck can't be read.
  ///
  /// Note: NHC doesn't send CORS headers, so on the web build this returns
  /// an empty list; Android / iOS are unaffected.
  static Future<List<TropicalStorm>> _fetch() async {
    final r = await http
        .get(
          Uri.parse('https://www.nhc.noaa.gov/CurrentStorms.json'),
          headers: _ua,
        )
        .timeout(_timeout);
    if (r.statusCode != 200) return [];
    final storms = parseCurrentStorms(r.body);
    return [for (final s in storms) await _withTrail(s)];
  }

  static Future<TropicalStorm> _withTrail(TropicalStorm s) async {
    try {
      // al092026 -> bal092026.dat
      final r = await http
          .get(
            Uri.parse(
              'https://ftp.nhc.noaa.gov/atcf/btk/b${s.id.toLowerCase()}.dat',
            ),
            headers: _ua,
          )
          .timeout(_timeout);
      if (r.statusCode != 200) return s;
      final track = stormFromBdeck(s.id, s.name, s.type, r.body);
      if (track == null || track.trail.length < 2) return s;
      return s.withTrail(track.trail);
    } catch (_) {
      return s;
    }
  }

  static const _classNames = {
    'HU': 'Hurricane',
    'TS': 'Tropical Storm',
    'TD': 'Tropical Depression',
    'STS': 'Subtropical Storm',
    'SS': 'Subtropical Storm',
    'SD': 'Subtropical Depression',
    'PTC': 'Post-Tropical Cyclone',
    'PC': 'Potential Tropical Cyclone',
  };

  /// Parses NHC's CurrentStorms.json. Numbers in that feed are sometimes
  /// strings ("105"), so everything is read leniently; storms missing a
  /// position are skipped.
  @visibleForTesting
  static List<TropicalStorm> parseCurrentStorms(String body) {
    final j = jsonDecode(body);
    final list = (j is Map ? j['activeStorms'] : null) as List? ?? const [];
    double? numOf(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.trim());
    final out = <TropicalStorm>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final lat = numOf(raw['latitudeNumeric']);
      final lon = numOf(raw['longitudeNumeric']);
      if (lat == null || lon == null) continue;
      final cls = '${raw['classification'] ?? ''}'.toUpperCase();
      final moveMph = numOf(raw['movementSpeed']) ?? 0;
      out.add(
        TropicalStorm(
          id: '${raw['id'] ?? ''}',
          name: '${raw['name'] ?? 'Unnamed'}',
          type: _classNames[cls] ?? 'Tropical Cyclone',
          lat: lat,
          lon: lon,
          windKt: (numOf(raw['intensity']) ?? 0).round(),
          pressureMb: (numOf(raw['pressure']) ?? 0).round(),
          time:
              DateTime.tryParse('${raw['lastUpdate'] ?? ''}')?.toUtc() ??
              DateTime.now().toUtc(),
          trail: const [],
          moveDirDeg: numOf(raw['movementDir']) ?? 0,
          moveKt: moveMph / 1.15078,
        ),
      );
    }
    return out;
  }

  /// Parses an ATCF b-deck body into a storm. B-decks repeat each fix on
  /// several lines (one per 34/50/64-kt wind radius), so fixes are merged
  /// per timestamp — otherwise motion was measured between two copies of
  /// the same fix and read "moving N at 0 mph".
  @visibleForTesting
  static TropicalStorm? stormFromBdeck(
    String id,
    String name,
    String type,
    String body,
  ) {
    final byTime = <DateTime, _BdeckFix>{};
    for (final line in const LineSplitter().convert(body)) {
      final c = line.split(',');
      if (c.length < 11) continue;
      if (c[4].trim() != 'BEST') continue;
      try {
        final dt = c[2].trim(); // YYYYMMDDHH
        final time = DateTime.utc(
          int.parse(dt.substring(0, 4)),
          int.parse(dt.substring(4, 6)),
          int.parse(dt.substring(6, 8)),
          int.parse(dt.substring(8, 10)),
        );
        byTime[time] = _BdeckFix(
          time,
          _parseLat(c[6].trim()),
          _parseLon(c[7].trim()),
          int.parse(c[8].trim()),
          int.parse(c[9].trim()),
        );
      } catch (_) {
        continue;
      }
    }
    if (byTime.isEmpty) return null;
    final fixes = byTime.values.toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    final cur = fixes.last;
    final trail = fixes.length > 12 ? fixes.sublist(fixes.length - 12) : fixes;

    // Movement from the previous two fixes.
    var moveDir = 0.0, moveKt = 0.0;
    if (fixes.length >= 2) {
      final a = fixes[fixes.length - 2], b = cur;
      final hours = b.time.difference(a.time).inMinutes / 60.0;
      if (hours > 0) {
        final dLat = (b.lat - a.lat) * 60; // nm
        final dLon =
            (b.lon - a.lon) *
            60 *
            math.cos((a.lat + b.lat) / 2 * math.pi / 180);
        final distNm = math.sqrt(dLat * dLat + dLon * dLon);
        moveKt = distNm / hours;
        moveDir = (math.atan2(dLon, dLat) * 180 / math.pi + 360) % 360;
      }
    }

    return TropicalStorm(
      id: id,
      name: name,
      type: type,
      lat: cur.lat,
      lon: cur.lon,
      windKt: cur.windKt,
      pressureMb: cur.pressureMb,
      time: cur.time,
      trail: [for (final f in trail) LatLng(f.lat, f.lon)],
      moveDirDeg: moveDir,
      moveKt: moveKt,
    );
  }

  static double _parseLat(String s) {
    // "285N" -> 28.5
    final v = double.parse(s.substring(0, s.length - 1)) / 10;
    return s.endsWith('S') ? -v : v;
  }

  static double _parseLon(String s) {
    // "871W" -> -87.1
    final v = double.parse(s.substring(0, s.length - 1)) / 10;
    return s.endsWith('W') ? -v : v;
  }
}
