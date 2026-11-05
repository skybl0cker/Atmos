import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/alert.dart';
import '../services/nearby_threats.dart';
import '../state/app_state.dart';
import '../widgets/art_icon.dart';
import '../widgets/scene.dart';
import '../widgets/scene_page.dart';
import '../widgets/storm_map.dart';

/// Everything that could affect the place on screen: its NWS watches and
/// warnings, plus — only when they're actually close — tropical cyclones
/// within 500 mi and M5+ earthquakes within 300 mi.
class AlertsScreen extends StatefulWidget {
  /// Re-check nearby storms / quakes when opened (off in widget tests).
  final bool refreshOnOpen;
  const AlertsScreen({super.key, this.refreshOnOpen = true});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  @override
  void initState() {
    super.initState();
    if (!widget.refreshOnOpen) return;
    // Freshen the nearby check whenever the screen is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshNearby();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final alerts = s.alerts;
    final near = s.nearby;
    final pal = SheetPalette.of(context);
    final allClear = alerts.isEmpty && near.isEmpty;

    return ScenePage(
      title: 'Alerts',
      subtitle: s.selected?.name,
      sceneHeight: 0.26,
      body: RefreshIndicator(
        color: const Color(0xFF6C63FF),
        onRefresh: () => s.refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
          children: [
            if (allClear) ...[
              const SizedBox(height: 40),
              const Center(child: ArtIcon(0, day: true, size: 80)),
              const SizedBox(height: 18),
              Text(
                'All clear',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: pal.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'No weather alerts for this location.',
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.soft, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                s.loadingNearby
                    ? 'Checking for nearby storms and earthquakes…'
                    : 'No hurricanes within ${stormRadiusMi.round()} mi or '
                          'M${quakeMinMag.toStringAsFixed(0)}+ earthquakes within '
                          '${quakeRadiusMi.round()} mi this week.',
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.soft, fontSize: 12, height: 1.4),
              ),
            ] else ...[
              const _Label('Weather alerts'),
              if (alerts.isEmpty)
                _note(pal, 'No watches or warnings for this location.')
              else
                for (var i = 0; i < alerts.length; i++) ...[
                  _AlertCard(alerts[i], initiallyOpen: i == 0),
                  const SizedBox(height: 10),
                ],
              if (!near.isEmpty) ...[
                const _Label('Nearby'),
                for (final n in near.storms) ...[
                  _StormCard(n),
                  const SizedBox(height: 10),
                ],
                for (final q in near.quakes) ...[
                  _QuakeCard(q),
                  const SizedBox(height: 10),
                ],
              ],
            ],
            const SizedBox(height: 16),
            Text(
              'Sources: National Weather Service · National Hurricane Center · USGS',
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.soft, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final pal = SheetPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: pal.soft,
          fontSize: 11,
          letterSpacing: 1.3,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

Widget _note(SheetPalette pal, String text) => Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: pal.card,
    borderRadius: BorderRadius.circular(18),
  ),
  child: Text(text, style: TextStyle(color: pal.soft, fontSize: 13)),
);

String _ago(DateTime t) {
  final d = DateTime.now().toUtc().difference(t.toUtc());
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} hr ago';
  return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
}

/// A tropical cyclone within range: intensity, distance, motion, and its
/// recent track on a map.
class _StormCard extends StatelessWidget {
  final NearbyStorm n;
  const _StormCard(this.n);

  @override
  Widget build(BuildContext context) {
    final pal = SheetPalette.of(context);
    final s = n.storm;
    final color = s.category >= 3
        ? const Color(0xFFFF4D5E)
        : s.category >= 1
        ? const Color(0xFFFF8A3C)
        : const Color(0xFFFFB524);
    final moving = s.moveMph > 0
        ? 'moving ${s.moveCompass} at ${s.moveMph} mph'
        : 'stationary';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(22),
        border: Border(left: BorderSide(color: color, width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withAlpha(pal.dark ? 60 : 32),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.cyclone, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.type} ${s.name}',
                      style: TextStyle(
                        color: pal.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${s.categoryLabel} · ${s.windMph} mph winds · ${n.miles.round()} mi away',
                      style: TextStyle(color: pal.soft, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Last update ${_ago(s.time)}, $moving.',
            style: TextStyle(color: pal.ink, fontSize: 13),
          ),
          const SizedBox(height: 10),
          StormMap(
            name: s.name,
            position: LatLng(s.lat, s.lon),
            trail: s.trail,
            height: 200,
          ),
          const SizedBox(height: 8),
          Text(
            'Follow the National Hurricane Center and local officials for watches, warnings and evacuation orders.',
            style: TextStyle(color: pal.soft, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// A recent M5+ earthquake within range. Taps through to the USGS page.
class _QuakeCard extends StatelessWidget {
  final NearbyQuake n;
  const _QuakeCard(this.n);

  @override
  Widget build(BuildContext context) {
    final q = n.quake;
    final color = q.mag >= 7
        ? const Color(0xFFFF4D5E)
        : q.mag >= 6
        ? const Color(0xFFFF8A3C)
        : const Color(0xFFFFB524);
    final pal = SheetPalette.of(context);
    return Material(
      color: pal.card,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: q.url.isEmpty
            ? null
            : () => launchUrl(
                Uri.parse(q.url),
                mode: LaunchMode.externalApplication,
              ),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 5)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withAlpha(pal.dark ? 60 : 32),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  q.mag.toStringAsFixed(1),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Earthquake · ${n.miles.round()} mi away',
                      style: TextStyle(
                        color: pal.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${q.place} · ${_ago(q.time)}'
                      '${q.tsunami == 1 ? ' · tsunami possible' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: pal.soft, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (q.url.isNotEmpty)
                Icon(Icons.open_in_new_rounded, size: 18, color: pal.faint),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertCard extends StatefulWidget {
  final WeatherAlert a;
  final bool initiallyOpen;
  const _AlertCard(this.a, {this.initiallyOpen = false});

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final pal = SheetPalette.of(context);
    final color = a.isSevere
        ? const Color(0xFFFF4D5E)
        : const Color(0xFFFF9A3C);
    return Material(
      color: pal.card,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 5)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withAlpha(pal.dark ? 60 : 32),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.event,
                          style: TextStyle(
                            color: pal.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _chip(
                              a.severity.isEmpty ? 'Advisory' : a.severity,
                              color,
                            ),
                            if (a.expires != null)
                              _chip(
                                'Until ${DateFormat.MMMd().add_jm().format(a.expires!)}',
                                pal.soft,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(Icons.expand_more_rounded, color: pal.soft),
                  ),
                ],
              ),
              if (a.areas.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    a.areas,
                    maxLines: _open ? 6 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: pal.soft, fontSize: 12),
                  ),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !_open
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (a.description.isNotEmpty)
                              Text(
                                a.description,
                                style: TextStyle(
                                  color: pal.ink,
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                            if (a.instruction.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: color.withAlpha(pal.dark ? 40 : 20),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'What to do',
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      a.instruction,
                                      style: TextStyle(
                                        color: pal.ink,
                                        fontSize: 13,
                                        height: 1.45,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withAlpha(30),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}
