import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../models/weather.dart';
import '../state/app_state.dart';
import 'scene.dart';

/// Expected precipitation in 15-minute steps (the Open-Meteo nowcast) as a
/// small bar chart — "what's coming" over the next [hours].
class NowcastStrip extends StatelessWidget {
  final List<MinutelyPoint> minutely;
  final int hours;
  final String? title;
  const NowcastStrip({
    super.key,
    required this.minutely,
    this.hours = 4,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = SheetPalette.of(context);
    final pts = minutely.take(hours * 4).toList();
    if (pts.isEmpty) return const SizedBox.shrink();
    final peak = pts.fold<double>(0, (m, p) => p.precipMm > m ? p.precipMm : m);
    final label = TextStyle(fontSize: 10, color: pal.soft);
    final mid = pts.length ~/ 2;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title ?? 'Next $hours hours',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: pal.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  peak <= 0 ? 'No rain expected' : 'Peak ${s.precip(peak)}/h',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: pal.soft, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final p in pts)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Tooltip(
                        message:
                            '${DateFormat('h:mm a').format(p.time)} · ${p.precipProb}% · ${s.precip(p.precipMm)}/h',
                        child: Container(
                          height: peak <= 0
                              ? 3
                              : 3 + 36 * (p.precipMm / peak).clamp(0, 1),
                          decoration: BoxDecoration(
                            color: p.precipMm > 0
                                ? const Color(0xFF3D9BFF)
                                : pal.track,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(DateFormat('h:mm a').format(pts.first.time), style: label),
              if (pts.length > 2)
                Text(DateFormat('h:mm a').format(pts[mid].time), style: label),
              Text(DateFormat('h:mm a').format(pts.last.time), style: label),
            ],
          ),
        ],
      ),
    );
  }
}
