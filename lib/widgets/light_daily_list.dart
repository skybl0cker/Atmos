import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'art_icon.dart';
import '../utils/temp_color.dart';
import 'scene.dart';

/// Clean daily rows for the white sheet: day, illustrated icon, rain
/// chance, low · range bar · high. Tap a row for sunrise / sunset / UV.
class LightDailyList extends StatefulWidget {
  final int maxDays;
  const LightDailyList({super.key, this.maxDays = 10});

  @override
  State<LightDailyList> createState() => _LightDailyListState();
}

class _LightDailyListState extends State<LightDailyList> {
  int? _open;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = SheetPalette.of(context);
    final all = s.data?.daily ?? const [];
    if (all.isEmpty) return const SizedBox.shrink();
    final days = all.take(widget.maxDays).toList();
    final lo = days.map((d) => d.minC).reduce(math.min);
    final hi = days.map((d) => d.maxC).reduce(math.max);
    final range = math.max(hi - lo, 1.0);

    return Column(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _open = _open == i ? null : i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 58,
                    child: Text(
                      i == 0 ? 'Today' : DateFormat.E().format(days[i].date),
                      style: TextStyle(
                          color: pal.ink,
                          fontSize: 15,
                          fontWeight:
                              i == 0 ? FontWeight.w600 : FontWeight.w400),
                    ),
                  ),
                  ArtIcon(days[i].code,
                      day: true, size: 30, onDark: pal.dark),
                  SizedBox(
                    width: 44,
                    child: Text(
                      days[i].precipProb >= 20 ? '${days[i].precipProb}%' : '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFF3D9BFF),
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(s.temp(days[i].minC),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: pal.soft, fontSize: 14)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LayoutBuilder(builder: (_, box) {
                      final w = box.maxWidth;
                      final left = (days[i].minC - lo) / range * w;
                      final width = math.max(
                          (days[i].maxC - days[i].minC) / range * w, 8.0);
                      return Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: pal.track,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Stack(children: [
                          Positioned(
                            left: left
                                .clamp(0.0, math.max(w - 8, 0.0))
                                .toDouble(),
                            width: width,
                            top: 0,
                            bottom: 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                gradient: LinearGradient(colors: [
                                  tempColor(days[i].minC),
                                  tempColor(days[i].maxC),
                                ]),
                              ),
                            ),
                          ),
                        ]),
                      );
                    }),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 34,
                    child: Text(s.temp(days[i].maxC),
                        style: TextStyle(
                            color: pal.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: _open == i
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                    child: Row(children: [
                      _fact(pal, Icons.wb_twilight_rounded, 'Sunrise',
                          DateFormat.jm().format(days[i].sunrise)),
                      _fact(pal, Icons.nights_stay_outlined, 'Sunset',
                          DateFormat.jm().format(days[i].sunset)),
                      _fact(pal, Icons.wb_sunny_outlined, 'UV',
                          days[i].uv.round().toString()),
                      _fact(pal, Icons.water_drop_outlined, 'Rain',
                          '${days[i].precipProb}%'),
                    ]),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ],
    );
  }

  Widget _fact(SheetPalette pal, IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Icon(icon, size: 16, color: pal.soft),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              style: TextStyle(
                  color: pal.ink, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(label, style: TextStyle(color: pal.soft, fontSize: 10)),
        ]),
      ),
    );
  }
}
