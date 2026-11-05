import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import '../models/alert.dart';
import '../state/app_state.dart';
import '../widgets/art_icon.dart';
import '../widgets/scene.dart';
import '../widgets/scene_page.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final alerts = s.alerts;
    final pal = SheetPalette.of(context);
    return ScenePage(
      title: 'Active Alerts',
      subtitle: s.selected?.name,
      sceneHeight: 0.26,
      body: alerts.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(32, 56, 32, 32),
              children: [
                const Center(child: ArtIcon(0, day: true, size: 80)),
                const SizedBox(height: 18),
                Text('All clear',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: pal.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('No active weather alerts for this location.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: pal.soft, fontSize: 14)),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 28),
              itemCount: alerts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _AlertCard(alerts[i], initiallyOpen: i == 0),
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
    final color =
        a.isSevere ? const Color(0xFFFF4D5E) : const Color(0xFFFF9A3C);
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
                    child: Icon(Icons.warning_amber_rounded,
                        color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.event,
                            style: TextStyle(
                                color: pal.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _chip(a.severity.isEmpty ? 'Advisory' : a.severity,
                                color),
                            if (a.expires != null)
                              _chip(
                                  'Until ${DateFormat.MMMd().add_jm().format(a.expires!)}',
                                  pal.soft),
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
                  child: Text(a.areas,
                      maxLines: _open ? 6 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: pal.soft, fontSize: 12)),
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
                              Text(a.description,
                                  style: TextStyle(
                                      color: pal.ink,
                                      fontSize: 13,
                                      height: 1.45)),
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
                                    Text('What to do',
                                        style: TextStyle(
                                            color: color,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text(a.instruction,
                                        style: TextStyle(
                                            color: pal.ink,
                                            fontSize: 13,
                                            height: 1.45)),
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
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}
