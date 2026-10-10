import 'dart:convert';
import 'dart:math' as math;

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

  /// Saffir-Simpson category 1-5, or 0 for tropical storm/depression.
  int get category {
    if (windKt >= 137) return 5;
    if (windKt >= 113) return 4;
    if (windKt >= 96) return 3;
    if (windKt >= 83) return 2;
    if (windKt >= 64) return 1;
    return 0;
  }

  String get categoryLabel =>
      category > 0 ? 'Category $category' : type;

  String get moveCompass {
    const dirs = [
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
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
  const _BdeckFix(
      this.time, this.lat, this.lon, this.windKt, this.pressureMb);
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

  static Future<List<TropicalStorm>> _fetch() async {
    final r = await http
        .get(Uri.parse('https://www.nhc.noaa.gov/'),
            headers: {'User-Agent': 'Mozilla/5.0'})
        .timeout(_timeout);
    if (r.statusCode != 200) return [];

    // <!--storm identification: AL092026 Hurricane Isaias-->
    final ids = RegExp(r'storm identification:\s*([A-Z]{2}\d{6})')
        .allMatches(r.body)
        .map((m) => m.group(1)!)
        .toSet()
        .toList();
    // <b>...<a name="Isaias"></a>Hurricane Isaias</b>
    final names = RegExp(
            r'<b>(?:<!--.*?-->)*<a name="([A-Za-z]+)"></a>([^<]+)</b>')
        .allMatches(r.body)
        .map((m) => m.group(2)!.trim())
        .toList();

    final storms = <TropicalStorm>[];
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      final fullName = i < names.length ? names[i] : '';
      // "Hurricane Isaias" -> type="Hurricane", name="Isaias"
      final parts = fullName.split(' ');
      final type = parts.length > 1
          ? parts.sublist(0, parts.length - 1).join(' ')
          : 'Tropical Cyclone';
      final name =
          parts.isNotEmpty ? parts.last : id;
      final storm = await _fetchStorm(id, name, type);
      if (storm != null) storms.add(storm);
    }
    return storms;
  }

  static Future<TropicalStorm?> _fetchStorm(
      String id, String name, String type) async {
    // AL092026 -> bal092026.dat ; EP202026 -> bep202026.dat
    final basin = id.substring(0, 2).toLowerCase();
    final file = 'b$basin${id.substring(2)}.dat';
    final r = await http
        .get(Uri.parse('https://ftp.nhc.noaa.gov/atcf/btk/$file'),
            headers: {'User-Agent': 'Mozilla/5.0'})
        .timeout(_timeout);
    if (r.statusCode != 200) return null;

    final fixes = <_BdeckFix>[];
    for (final line in const LineSplitter().convert(r.body)) {
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
        fixes.add(_BdeckFix(
          time,
          _parseLat(c[6].trim()),
          _parseLon(c[7].trim()),
          int.parse(c[8].trim()),
          int.parse(c[9].trim()),
        ));
      } catch (_) {
        continue;
      }
    }
    if (fixes.isEmpty) return null;
    final cur = fixes.last;
    final trail = fixes.length > 12
        ? fixes.sublist(fixes.length - 12)
        : fixes;

    // Movement from the previous two fixes.
    var moveDir = 0.0, moveKt = 0.0;
    if (fixes.length >= 2) {
      final a = fixes[fixes.length - 2], b = cur;
      final hours =
          b.time.difference(a.time).inMinutes / 60.0;
      if (hours > 0) {
        final dLat = (b.lat - a.lat) * 60; // nm
        final dLon = (b.lon - a.lon) *
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
