import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'tropical_service.dart';
import 'usgs_service.dart';

/// The current headline severe-weather event in the US, derived from live
/// NWS alerts — drives the dynamic 4th tab (icon + label follow whatever
/// is actually happening: hurricane, tornado outbreak, etc.).
enum SevereKind {
  none,
  hurricane,
  typhoon,
  tornadoEmergency,
  quakeMajor, // M7.0+
  tornado,
  flashFlood,
  quake, // M6.0+
  stormSurge,
  extremeWind,
  dustStorm,
  winterStorm,
  tornadoWatch,
  severeStorm,
}

class SevereEvent {
  final SevereKind kind;
  final String title;
  final String headline;
  final String areas;
  final String description;
  final String instruction;
  final String? effective;
  final String? expires;
  final int alertCount;

  const SevereEvent({
    required this.kind,
    required this.title,
    required this.headline,
    required this.areas,
    required this.description,
    required this.instruction,
    this.effective,
    this.expires,
    this.alertCount = 1,
  });

  /// Tab label, e.g. "Hurricane", "Tornado", "Alerts".
  String get tabLabel {
    switch (kind) {
      case SevereKind.none:
        return 'Alerts';
      case SevereKind.hurricane:
        return 'Hurricane';
      case SevereKind.typhoon:
        return 'Typhoon';
      case SevereKind.tornadoEmergency:
        return 'Tornado Emg';
      case SevereKind.quakeMajor:
      case SevereKind.quake:
        return 'Quake';
      case SevereKind.tornado:
        return 'Tornado';
      case SevereKind.flashFlood:
        return 'Flash Flood';
      case SevereKind.stormSurge:
        return 'Storm Surge';
      case SevereKind.extremeWind:
        return 'Extrm Wind';
      case SevereKind.dustStorm:
        return 'Dust Storm';
      case SevereKind.winterStorm:
        return 'Winter Storm';
      case SevereKind.tornadoWatch:
        return 'Tor Watch';
      case SevereKind.severeStorm:
        return 'Severe Wx';
    }
  }

  IconData get tabIcon {
    switch (kind) {
      case SevereKind.none:
        return Icons.notifications_outlined;
      case SevereKind.hurricane:
      case SevereKind.typhoon:
        return Icons.cyclone;
      case SevereKind.tornadoEmergency:
      case SevereKind.tornado:
      case SevereKind.tornadoWatch:
        return Icons.tornado;
      case SevereKind.quakeMajor:
      case SevereKind.quake:
        return Icons.vibration;
      case SevereKind.flashFlood:
        return Icons.flood;
      case SevereKind.stormSurge:
        return Icons.tsunami;
      case SevereKind.extremeWind:
        return Icons.air;
      case SevereKind.dustStorm:
        return Icons.storm;
      case SevereKind.winterStorm:
        return Icons.ac_unit;
      case SevereKind.severeStorm:
        return Icons.thunderstorm;
    }
  }

  Color get color {
    switch (kind) {
      case SevereKind.none:
        return Colors.grey;
      case SevereKind.hurricane:
      case SevereKind.typhoon:
      case SevereKind.tornadoEmergency:
        return Colors.red;
      case SevereKind.quakeMajor:
        return Colors.deepOrange;
      case SevereKind.quake:
        return Colors.orange;
      case SevereKind.tornado:
      case SevereKind.flashFlood:
      case SevereKind.extremeWind:
        return Colors.orange;
      default:
        return Colors.amber;
    }
  }
}

class _Hit {
  final SevereKind kind;
  final Map<String, dynamic> props;
  _Hit(this.kind, this.props);
}

class SevereEventService {
  static const _api = 'https://api.weather.gov/alerts/active';
  static const _cacheTtl = Duration(minutes: 10);
  static SevereEvent? _cache;
  static DateTime? _fetched;

  // NWS event names to query, most to least urgent.
  static const _events = [
    'Hurricane Warning',
    'Typhoon Warning',
    'Tornado Warning',
    'Flash Flood Warning',
    'Storm Surge Warning',
    'Extreme Wind Warning',
    'Dust Storm Warning',
    'Blizzard Warning',
    'Ice Storm Warning',
    'Tornado Watch',
    'Severe Thunderstorm Watch',
  ];

  /// Returns the current headline event, or a kind=none placeholder when
  /// nothing major is active. Considers NWS warnings and major
  /// earthquakes, highest priority wins.
  static Future<SevereEvent> current() async {
    if (_cache != null &&
        _fetched != null &&
        DateTime.now().difference(_fetched!) < _cacheTtl) {
      return _cache!;
    }
    SevereEvent event;
    try {
      final results = await Future.wait([
        _fetch(),
        _quakeEvent().catchError((_) => null),
        _tropicalEvent().catchError((_) => null),
      ]);
      final nws = results[0] ?? _none();
      final quake = results[1];
      final tropical = results[2];
      event = nws;
      for (final cand in [quake, tropical]) {
        if (cand != null &&
            (event.kind == SevereKind.none ||
                cand.kind.index < event.kind.index)) {
          event = cand;
        }
      }
    } catch (_) {
      event = _none();
    }
    _cache = event;
    _fetched = DateTime.now();
    return event;
  }

  /// Builds a quake event from the strongest recent significant quake, or
  /// null when nothing reaches M6.0.
  static Future<SevereEvent?> _quakeEvent() async {
    final quakes = await UsgsService.significant();
    if (quakes.isEmpty) return null;
    final q = quakes.reduce((a, b) => a.mag >= b.mag ? a : b);
    if (q.mag < 6.0) return null;
    final kind =
        q.mag >= 7.0 ? SevereKind.quakeMajor : SevereKind.quake;
    final ago = _ago(q.time);
    return SevereEvent(
      kind: kind,
      title: 'M${q.mag.toStringAsFixed(1)} Earthquake',
      headline: q.place,
      areas: q.place,
      description:
          'A magnitude ${q.mag.toStringAsFixed(1)} earthquake struck '
          '${q.place} $ago.'
          '${q.tsunami == 1 ? ' A tsunami is possible — if you are near the coast, move to high ground immediately.' : ''}',
      instruction: q.tsunami == 1
          ? 'Tsunami possible. Move to high ground immediately and follow local emergency guidance.'
          : 'Drop, Cover, and Hold On. Expect aftershocks.',
    );
  }

  /// Builds a hurricane event from the strongest active NHC hurricane.
  /// Covers the gap when NWS warnings lapse but the storm itself is
  /// still a major threat (e.g. around landfall).
  static Future<SevereEvent?> _tropicalEvent() async {
    final storms = await TropicalService.activeStorms();
    final hurricanes =
        storms.where((s) => s.category >= 1).toList();
    if (hurricanes.isEmpty) return null;
    hurricanes
        .sort((a, b) => b.windKt.compareTo(a.windKt));
    final s = hurricanes.first;
    final moveMph = (s.moveKt * 1.15078).round();
    return SevereEvent(
      kind: SevereKind.hurricane,
      title: 'Hurricane ${s.name}',
      headline:
          '${s.categoryLabel} · ${s.windMph} mph sustained',
      areas:
          'Last position ${s.lat.toStringAsFixed(1)}°N '
          '${s.lon.abs().toStringAsFixed(1)}°W',
      description:
          'Hurricane ${s.name} is a ${s.categoryLabel.toLowerCase()} '
          'with ${s.windMph} mph sustained winds and a central '
          'pressure of ${s.pressureMb} mb, moving ${s.moveCompass} '
          'at $moveMph mph (latest NHC best-track).',
      instruction:
          'Follow guidance from the National Hurricane Center and local emergency officials.',
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().toUtc().difference(t.toUtc());
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} hr ago';
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  }

  static SevereEvent _none() => const SevereEvent(
        kind: SevereKind.none,
        title: 'No major events',
        headline: 'No major severe weather events are active nationwide.',
        areas: 'United States',
        description:
            'The National Weather Service has no hurricane, tornado, flash '
            'flood, storm surge, extreme wind, dust storm, or winter storm '
            'warnings in effect right now.',
        instruction: '',
      );

  static Future<SevereEvent> _fetch() async {
    // NOTE: api.weather.gov does not OR multiple `event` params (only the
    // last is honored), so query each event separately in parallel.
    final futures = _events.map((e) => _fetchEvent(e).catchError((_) =>
        <Map<String, dynamic>>[]));
    final results = await Future.wait(futures);
    final features = results.expand((l) => l).toList();

    final hits = <_Hit>[];
    for (final f in features) {
      final p = (f['properties'] as Map).cast<String, dynamic>();
      final kind = _classify(p);
      if (kind != SevereKind.none) hits.add(_Hit(kind, p));
    }
    if (hits.isEmpty) return _none();

    // Highest priority = lowest index.
    hits.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    final top = hits.first;
    final sameKind =
        hits.where((h) => h.kind == top.kind).toList();
    final p = top.props;
    final areas = _shortAreas((p['areaDesc'] as String?) ?? '');
    return SevereEvent(
      kind: top.kind,
      title: _title(top.kind, p),
      headline: (p['headline'] as String?) ?? '',
      areas: areas,
      description: (p['description'] as String?) ?? '',
      instruction: (p['instruction'] as String?) ?? '',
      effective: p['effective'] as String?,
      expires: p['expires'] as String?,
      alertCount: sameKind.length,
    );
  }

  static Future<List<Map<String, dynamic>>> _fetchEvent(
      String event) async {
    final uri = Uri.parse(
        '$_api?status=actual&message_type=alert'
        '&event=${Uri.encodeComponent(event)}');
    final r = await http.get(uri, headers: {
      'User-Agent': 'com.skybl0cker.atmos',
      'Accept': 'application/geo+json',
    }).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return [];
    return ((jsonDecode(r.body) as Map<String, dynamic>)['features']
            as List)
        .cast<Map<String, dynamic>>();
  }

  /// Maps an NWS alert to a kind. Tornado/flash-flood emergencies are
  /// detected via headline tags and damage-threat parameters.
  static SevereKind _classify(Map<String, dynamic> p) {
    final event = (p['event'] as String?) ?? '';
    final headline = ((p['headline'] as String?) ?? '').toUpperCase();
    String threat(Map<String, dynamic> p) {
      final params =
          (p['parameters'] as Map?)?.cast<String, dynamic>() ?? {};
      final t = params['tornadoDamageThreat'];
      if (t is List && t.isNotEmpty) return t.first.toString().toUpperCase();
      return '';
    }

    switch (event) {
      case 'Hurricane Warning':
        return SevereKind.hurricane;
      case 'Typhoon Warning':
        return SevereKind.typhoon;
      case 'Tornado Warning':
        final dt = threat(p);
        if (headline.contains('TORNADO EMERGENCY') ||
            dt.contains('CATASTROPHIC')) {
          return SevereKind.tornadoEmergency;
        }
        return SevereKind.tornado;
      case 'Flash Flood Warning':
        // Only emergencies take the tab; ordinary flash flood warnings
        // are common enough to be noise.
        if (headline.contains('FLASH FLOOD EMERGENCY')) {
          return SevereKind.flashFlood;
        }
        return SevereKind.none;
      case 'Storm Surge Warning':
        return SevereKind.stormSurge;
      case 'Extreme Wind Warning':
        return SevereKind.extremeWind;
      case 'Dust Storm Warning':
        return SevereKind.dustStorm;
      case 'Blizzard Warning':
      case 'Ice Storm Warning':
        return SevereKind.winterStorm;
      case 'Tornado Watch':
        // Only particularly dangerous situations take the tab.
        if (headline.contains('PARTICULARLY DANGEROUS')) {
          return SevereKind.tornadoWatch;
        }
        return SevereKind.none;
      case 'Severe Thunderstorm Watch':
        if (headline.contains('PARTICULARLY DANGEROUS')) {
          return SevereKind.severeStorm;
        }
        return SevereKind.none;
    }
    return SevereKind.none;
  }

  static String _title(SevereKind kind, Map<String, dynamic> p) {
    const names = {
      SevereKind.hurricane: 'Hurricane Warning',
      SevereKind.typhoon: 'Typhoon Warning',
      SevereKind.tornadoEmergency: 'Tornado Emergency',
      SevereKind.tornado: 'Tornado Warning',
      SevereKind.flashFlood: 'Flash Flood Emergency',
      SevereKind.stormSurge: 'Storm Surge Warning',
      SevereKind.extremeWind: 'Extreme Wind Warning',
      SevereKind.dustStorm: 'Dust Storm Warning',
      SevereKind.winterStorm: 'Winter Storm Warning',
      SevereKind.tornadoWatch: 'PDS Tornado Watch',
      SevereKind.severeStorm: 'PDS Severe Thunderstorm Watch',
      SevereKind.none: 'No major events',
    };
    return names[kind] ?? (p['event'] as String? ?? 'Severe Weather');
  }

  /// "Inland Bay; Coastal Bay; ..." -> first few areas, human-sized.
  static String _shortAreas(String areaDesc) {
    final parts = areaDesc
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length <= 3) return parts.join('; ');
    return '${parts.take(3).join('; ')} (+${parts.length - 3} more)';
  }
}
