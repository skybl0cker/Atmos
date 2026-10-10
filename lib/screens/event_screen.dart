import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/news_service.dart';
import '../services/severe_event_service.dart';
import '../services/tropical_service.dart';
import '../services/usgs_service.dart';
import '../state/app_state.dart';
import '../widgets/storm_map.dart';

/// Situation room: the 4th tab. Threats are ranked by distance from the
/// user — the closest one gets the full feature treatment (live stats,
/// map, news), the rest follow nearest-first.
class EventScreen extends StatefulWidget {
  const EventScreen({super.key});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

/// A hurricane or earthquake, ranked by distance from the user.
class _Threat {
  final TropicalStorm? storm;
  final Earthquake? quake;
  final double distanceMi; // double.infinity when location unknown
  const _Threat({this.storm, this.quake, required this.distanceMi});
  bool get isStorm => storm != null;
  String get title => isStorm
      ? '${storm!.type} ${storm!.name}'
      : 'M${quake!.mag.toStringAsFixed(1)} Earthquake';
}

class _EventScreenState extends State<EventScreen> {
  SevereEvent? _event;
  List<_Threat> _threats = [];
  List<NewsArticle> _news = [];
  List<List<LatLng>> _polygons = [];
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _event = null;
      _failed = false;
    });
    try {
      final userPlace =
          context.read<AppState>().selected;
      final userLoc = userPlace == null
          ? null
          : LatLng(userPlace.lat, userPlace.lon);

      final results = await Future.wait([
        SevereEventService.current(),
        TropicalService.activeStorms(),
        UsgsService.significant(),
      ]);
      final event = results[0] as SevereEvent;
      final storms = results[1] as List<TropicalStorm>;
      final quakes = (results[2] as List<Earthquake>)
          .where((q) => q.mag >= 6.0)
          .toList();

      final threats = _rank(storms, quakes, userLoc);

      // Feature content for the closest threat.
      List<NewsArticle> news = [];
      List<List<LatLng>> polygons = [];
      if (threats.isNotEmpty) {
        final top = threats.first;
        if (top.isStorm) {
          final s = top.storm!;
          final r = await Future.wait([
            NewsService.forQuery('${s.type} ${s.name}')
                .catchError((_) => <NewsArticle>[]),
            _warningPolygons()
                .catchError((_) => <List<LatLng>>[]),
          ]);
          news = r[0] as List<NewsArticle>;
          polygons = r[1] as List<List<LatLng>>;
        } else {
          final q = top.quake!;
          final region = q.place.contains(',')
              ? q.place.split(',').last.trim()
              : q.place;
          news = await NewsService.forQuery('earthquake $region')
              .catchError((_) => <NewsArticle>[]);
        }
      }

      if (mounted) {
        setState(() {
          _event = event;
          _threats = threats;
          _news = news;
          _polygons = polygons;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  static List<_Threat> _rank(List<TropicalStorm> storms,
      List<Earthquake> quakes, LatLng? userLoc) {
    const dist = Distance();
    double mi(LatLng p) => userLoc == null
        ? double.infinity
        : dist(userLoc, p) / 1609.34;
    final threats = <_Threat>[
      for (final s in storms)
        _Threat(
            storm: s,
            distanceMi: mi(LatLng(s.lat, s.lon))),
      for (final q in quakes)
        _Threat(
            quake: q, distanceMi: mi(q.location)),
    ];
    threats.sort((a, b) =>
        a.distanceMi.compareTo(b.distanceMi));
    return threats;
  }

  /// NWS hurricane-warning polygons for the map.
  static Future<List<List<LatLng>>> _warningPolygons() async {
    final uri = Uri.parse(
        'https://api.weather.gov/alerts/active?status=actual'
        '&message_type=alert&event=${Uri.encodeComponent('Hurricane Warning')}');
    final r = await http.get(uri, headers: {
      'User-Agent': 'com.skybl0cker.atmos',
      'Accept': 'application/geo+json',
    }).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return [];
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    final features =
        ((d['features'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
    return warningRings(features);
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset('assets/backgrounds/bg_rain.webp',
              fit: BoxFit.cover),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withAlpha(110),
                  Colors.black.withAlpha(190),
                ],
              ),
            ),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Severe Weather'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ],
        ),
      body: event == null
          ? Center(
              child: _failed
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Could not load alerts. Check your connection and tap refresh.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : const CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_threats.isNotEmpty) ...[
                    _FeaturedThreat(
                      threat: _threats.first,
                      polygons: _polygons,
                      news: _news,
                    ),
                    if (_threats.length > 1) ...[
                      const SizedBox(height: 16),
                      _FurtherOut(
                          threats: _threats.sublist(1)),
                    ],
                    const SizedBox(height: 16),
                  ],
                  _AlertSection(event: event),
                  const SizedBox(height: 24),
                  const Text(
                    'Sources: National Weather Service · National Hurricane Center · USGS',
                    style:
                        TextStyle(fontSize: 11, color: Colors.white38),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
      ),
      ],
    );
  }
}

String _distLabel(double mi) =>
    mi.isInfinite ? '' : '${mi.round()} mi away';

/// The closest threat, fully featured.
class _FeaturedThreat extends StatelessWidget {
  final _Threat threat;
  final List<List<LatLng>> polygons;
  final List<NewsArticle> news;
  const _FeaturedThreat({
    required this.threat,
    required this.polygons,
    required this.news,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Closest threat',
            style:
                TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (threat.isStorm)
          _HurricaneSection(
            storm: threat.storm!,
            distanceMi: threat.distanceMi,
            polygons: polygons,
            news: news,
          )
        else
          _QuakeFeature(
            quake: threat.quake!,
            distanceMi: threat.distanceMi,
            news: news,
          ),
      ],
    );
  }
}

class _HurricaneSection extends StatelessWidget {
  final TropicalStorm storm;
  final double distanceMi;
  final List<List<LatLng>> polygons;
  final List<NewsArticle> news;
  const _HurricaneSection({
    required this.storm,
    required this.distanceMi,
    required this.polygons,
    required this.news,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cyclone,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${storm.type} ${storm.name}',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${storm.categoryLabel} · ${storm.windMph} mph · ${storm.pressureMb} mb',
                    style: const TextStyle(
                        fontSize: 13, color: Colors.white70),
                  ),
                  if (!distanceMi.isInfinite)
                    Text(
                      _distLabel(distanceMi),
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StormMap(
          name: storm.name,
          position: LatLng(storm.lat, storm.lon),
          trail: storm.trail,
          warningPolygons: polygons,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatChip(Icons.air,
                'Wind', '${storm.windMph} mph'),
            _StatChip(Icons.compress,
                'Pressure', '${storm.pressureMb} mb'),
            _StatChip(Icons.navigation,
                'Moving',
                '${storm.moveCompass} at ${(storm.moveKt * 1.15078).round()} mph'),
          ],
        ),
        if (news.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Latest coverage',
              style:
                  TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final a in news) _NewsTile(article: a),
        ],
      ],
    );
  }
}

/// Featured earthquake: big magnitude, distance, tsunami flag, news.
class _QuakeFeature extends StatelessWidget {
  final Earthquake quake;
  final double distanceMi;
  final List<NewsArticle> news;
  const _QuakeFeature({
    required this.quake,
    required this.distanceMi,
    required this.news,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: Colors.deepOrange.withAlpha(30),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.deepOrange),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Colors.deepOrange,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          quake.mag.toStringAsFixed(1),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 22),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(quake.place,
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700)),
                          Text(_ago(quake.time),
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70)),
                          if (!distanceMi.isInfinite)
                            Text(
                              _distLabel(distanceMi),
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (quake.tsunami == 1) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.lightBlue.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.lightBlueAccent),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.tsunami,
                            color:
                                Colors.lightBlueAccent),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tsunami possible. If near the coast, move to high ground immediately.',
                            style: TextStyle(
                                fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (news.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Latest coverage',
              style:
                  TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final a in news) _NewsTile(article: a),
        ],
      ],
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().toUtc().difference(t.toUtc());
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} hr ago';
    return '${d.inDays}d ago';
  }
}

/// Everything else, nearest-first, compact.
class _FurtherOut extends StatelessWidget {
  final List<_Threat> threats;
  const _FurtherOut({required this.threats});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Further out',
            style:
                TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final t in threats)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: t.isStorm
                  ? const CircleAvatar(
                      backgroundColor: Colors.red,
                      child: Icon(Icons.cyclone,
                          color: Colors.white, size: 20),
                    )
                  : CircleAvatar(
                      backgroundColor: t.quake!.mag >= 7
                          ? Colors.red
                          : Colors.deepOrange,
                      child: Text(
                        t.quake!.mag.toStringAsFixed(1),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13),
                      ),
                    ),
              title: Text(t.title,
                  style: const TextStyle(fontSize: 14)),
              subtitle: t.isStorm
                  ? Text(
                      '${t.storm!.categoryLabel} · ${t.storm!.windMph} mph',
                      style:
                          const TextStyle(fontSize: 12))
                  : Text(t.quake!.place,
                      style:
                          const TextStyle(fontSize: 12)),
              trailing: t.distanceMi.isInfinite
                  ? null
                  : Text(_distLabel(t.distanceMi),
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70)),
            ),
          ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatChip(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white70),
          const SizedBox(width: 6),
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 12, color: Colors.white70)),
          Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _NewsTile extends StatelessWidget {
  final NewsArticle article;
  const _NewsTile({required this.article});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(article.title,
            style: const TextStyle(fontSize: 14)),
        subtitle: article.source.isNotEmpty
            ? Text(article.source,
                style: const TextStyle(fontSize: 12))
            : null,
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () => _open(article.url),
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri,
          mode: LaunchMode.externalApplication);
    }
  }
}

class _AlertSection extends StatelessWidget {
  final SevereEvent event;
  const _AlertSection({required this.event});

  @override
  Widget build(BuildContext context) {
    final quiet = event.kind == SevereKind.none;
    return Card(
      color: quiet ? null : event.color.withAlpha(28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: quiet
            ? BorderSide.none
            : BorderSide(color: event.color.withAlpha(120)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(event.tabIcon, size: 44, color: event.color),
            const SizedBox(height: 10),
            Text(
              event.title,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            if (event.headline.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                event.headline,
                style: const TextStyle(
                    fontSize: 13, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 10),
            Text(
              event.areas,
              style: const TextStyle(
                  fontSize: 13, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            if (event.instruction.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: event.color.withAlpha(36),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: event.color),
                ),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined,
                        color: event.color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(event.instruction,
                          style: const TextStyle(
                              fontSize: 13, height: 1.4)),
                    ),
                  ],
                ),
              ),
            ],
            if (event.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                event.description.length > 600
                    ? '${event.description.substring(0, 600)}…'
                    : event.description,
                style: const TextStyle(
                    fontSize: 13, height: 1.45),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
