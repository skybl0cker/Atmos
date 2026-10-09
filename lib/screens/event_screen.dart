import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/news_service.dart';
import '../services/severe_event_service.dart';
import '../services/tropical_service.dart';
import '../services/usgs_service.dart';
import '../widgets/storm_map.dart';

/// Situation room: the 4th tab. Whatever major event is happening —
/// hurricane, tornado outbreak, earthquake — gets the full treatment:
/// live stats, a map, and related news, TWC-style.
class EventScreen extends StatefulWidget {
  const EventScreen({super.key});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  SevereEvent? _event;
  List<TropicalStorm> _storms = [];
  List<Earthquake> _quakes = [];
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
      final results = await Future.wait([
        SevereEventService.current(),
        TropicalService.activeStorms(),
        UsgsService.significant(),
      ]);
      final event = results[0] as SevereEvent;
      final storms = results[1] as List<TropicalStorm>;
      final quakes = results[2] as List<Earthquake>;

      List<NewsArticle> news = [];
      List<List<LatLng>> polygons = [];
      final featured = _featuredStorm(storms);
      if (featured != null) {
        final nq = '${featured.type} ${featured.name}';
        final results2 = await Future.wait([
          NewsService.forQuery(nq)
              .catchError((_) => <NewsArticle>[]),
          _warningPolygons()
              .catchError((_) => <List<LatLng>>[]),
        ]);
        news = results2[0] as List<NewsArticle>;
        polygons = results2[1] as List<List<LatLng>>;
      }

      if (mounted) {
        setState(() {
          _event = event;
          _storms = storms;
          _quakes = quakes;
          _news = news;
          _polygons = polygons;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// The Atlantic hurricane takes the feature slot; otherwise the first
  /// active storm.
  TropicalStorm? _featuredStorm(List<TropicalStorm> storms) {
    if (storms.isEmpty) return null;
    for (final s in storms) {
      if (s.id.startsWith('AL')) return s;
    }
    return storms.first;
  }

  /// NWS hurricane-warning polygons for the map.
  static Future<List<List<LatLng>>> _warningPolygons() async {
    final uri = Uri.parse(
        'https://api.weather.gov/alerts/active?status=actual'
        '&message_type=alert&event=${Uri.encodeComponent('Hurricane Warning')}');
    final r = await http.get(uri, headers: {
      'User-Agent': 'com.example.skycast',
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
    return Scaffold(
      appBar: AppBar(
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
                  if (_featuredStorm(_storms) != null)
                    _HurricaneSection(
                      storm: _featuredStorm(_storms)!,
                      polygons: _polygons,
                      news: _news,
                    ),
                  if (_quakes.any((q) => q.mag >= 6.0)) ...[
                    const SizedBox(height: 16),
                    _QuakeSection(quakes: _quakes),
                  ],
                  const SizedBox(height: 16),
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
    );
  }
}

class _HurricaneSection extends StatelessWidget {
  final TropicalStorm storm;
  final List<List<LatLng>> polygons;
  final List<NewsArticle> news;
  const _HurricaneSection({
    required this.storm,
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
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _QuakeSection extends StatelessWidget {
  final List<Earthquake> quakes;
  const _QuakeSection({required this.quakes});

  @override
  Widget build(BuildContext context) {
    final big = quakes.where((q) => q.mag >= 6.0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recent significant earthquakes',
            style:
                TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final q in big.take(5))
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: q.mag >= 7
                      ? Colors.red
                      : Colors.deepOrange,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    q.mag.toStringAsFixed(1),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15),
                  ),
                ),
              ),
              title: Text(q.place,
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(_ago(q.time),
                  style: const TextStyle(fontSize: 12)),
              trailing: q.tsunami == 1
                  ? const Icon(Icons.tsunami,
                      color: Colors.lightBlueAccent)
                  : null,
              onTap: q.url.isNotEmpty
                  ? () async {
                      final uri = Uri.tryParse(q.url);
                      if (uri != null &&
                          await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode:
                                LaunchMode.externalApplication);
                      }
                    }
                  : null,
            ),
          ),
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
