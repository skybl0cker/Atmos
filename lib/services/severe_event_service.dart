import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// The current headline severe-weather event in the US, derived from live
/// NWS alerts — drives the dynamic 4th tab (icon + label follow whatever
/// is actually happening: hurricane, tornado outbreak, etc.).
enum SevereKind {
  none,
  hurricane,
  typhoon,
  tornadoEmergency,
  tornado,
  flashFlood,
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
  /// nothing major is active.
  static Future<SevereEvent> current() async {
    if (_cache != null &&
        _fetched != null &&
        DateTime.now().difference(_fetched!) < _cacheTtl) {
      return _cache!;
    }
    final event = await _fetch().catchError((_) => _none());
    _cache = event;
    _fetched = DateTime.now();
    return event;
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
    final query = _events
        .map((e) => 'event=${Uri.encodeComponent(e)}')
        .join('&');
    final uri = Uri.parse(
        '$_api?status=actual&message_type=alert&$query');
    final r = await http.get(uri, headers: {
      'User-Agent': 'com.example.skycast',
      'Accept': 'application/geo+json',
    }).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return _none();
    final features =
        ((jsonDecode(r.body) as Map<String, dynamic>)['features']
                as List)
            .cast<Map<String, dynamic>>();

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
