import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../models/weather.dart';
import '../services/climate_service.dart';
import '../state/app_state.dart';
import '../utils/forecast_changes.dart';
import '../utils/insights.dart';
import 'scene.dart';

const _accent = Color(0xFF6C63FF);

/// Rounded card in the sheet style with a small header.
class _Card extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final Widget child;
  const _Card({
    required this.icon,
    required this.color,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final pal = SheetPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: pal.soft,
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

String _hourLabel(DateTime t) =>
    DateFormat(t.minute == 0 ? 'h a' : 'h:mm a').format(t);

String _dayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final diff = DateTime(day.year, day.month, day.day).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  return DateFormat('EEEE').format(day);
}

// ---------------------------------------------------------------------------

/// "Best time outside": the most pleasant 2-hour daylight stretch ahead.
class BestTimeCard extends StatelessWidget {
  final AppState s;
  final WeatherData d;
  const BestTimeCard({super.key, required this.s, required this.d});

  static const _snagText = {
    OutdoorSnag.rain: 'rain chances stay high',
    OutdoorSnag.cold: 'it stays cold',
    OutdoorSnag.heat: "it's hot all day",
    OutdoorSnag.wind: "it's windy throughout",
    OutdoorSnag.sun: 'the sun is intense',
  };

  @override
  Widget build(BuildContext context) {
    final w = bestOutdoorWindow(d);
    if (w == null) return const SizedBox.shrink();
    final pal = SheetPalette.of(context);
    final when =
        '${_dayLabel(w.start, d.current.time)}, '
        '${_hourLabel(w.start)} – ${_hourLabel(w.end)}';
    final facts = [
      'feels ${s.temp(w.feelsC)}',
      w.rainChance < 15 ? 'dry' : '${w.rainChance}% rain',
    ].join(' · ');
    final color = w.isGood
        ? const Color(0xFF22B07D)
        : w.score >= 35
        ? const Color(0xFFFFB524)
        : const Color(0xFFFF7A59);

    return _Card(
      icon: Icons.directions_walk_rounded,
      color: color,
      title: 'Best time outside',
      child: Row(
        children: [
          // Score ring.
          SizedBox(
            width: 46,
            height: 46,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: w.score / 100,
                  strokeWidth: 4,
                  color: color,
                  backgroundColor: pal.track,
                  strokeCap: StrokeCap.round,
                ),
                Text(
                  '${w.score}',
                  style: TextStyle(
                    color: pal.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  when,
                  style: TextStyle(
                    color: pal.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  w.isGood || w.snag == null
                      ? facts
                      : 'Least bad window — ${_snagText[w.snag]}. $facts',
                  style: TextStyle(color: pal.soft, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// "This week": warmest day, coldest night, and the wettest / windiest day
/// when they stand out.
class WeekHighlightsCard extends StatelessWidget {
  final AppState s;
  final WeatherData d;
  const WeekHighlightsCard({super.key, required this.s, required this.d});

  @override
  Widget build(BuildContext context) {
    final items = weekHighlights(d);
    if (items.isEmpty) return const SizedBox.shrink();
    final pal = SheetPalette.of(context);
    Widget tile(WeekHighlight h) {
      final day = h.day;
      final (icon, color, label, value) = switch (h.kind) {
        HighlightKind.warmest => (
          Icons.wb_sunny_rounded,
          const Color(0xFFFF8A5B),
          'Warmest',
          s.temp(day.maxC),
        ),
        HighlightKind.coldest => (
          Icons.ac_unit_rounded,
          const Color(0xFF3D9BFF),
          'Coldest night',
          s.temp(day.minC),
        ),
        HighlightKind.wettest => (
          Icons.umbrella_rounded,
          const Color(0xFF3D9BFF),
          'Wettest',
          day.precipMm != null && day.precipMm! >= 0.5
              ? s.precip(day.precipMm!)
              : '${day.precipProb}%',
        ),
        HighlightKind.snowiest => (
          Icons.ac_unit_rounded,
          const Color(0xFF8FB8FF),
          'Most snow',
          s.snow(day.snowCm ?? 0),
        ),
        HighlightKind.windiest => (
          Icons.air_rounded,
          const Color(0xFF22B07D),
          'Windiest',
          s.wind(day.gustMaxKmh ?? day.windMaxKmh ?? 0),
        ),
      };
      final when = _dayLabel(day.date, d.current.time);
      return Container(
        width: 112,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: color.withAlpha(pal.dark ? 36 : 22),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: pal.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: pal.soft, fontSize: 11),
            ),
            Text(
              when,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: pal.ink,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return _Card(
      icon: Icons.insights_rounded,
      color: _accent,
      title: 'This week',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(children: [for (final h in items) tile(h)]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Today's low–high against the normal low–high for the date, drawn as two
/// range bars on a shared scale, with a one-line verdict.
class NormalCard extends StatelessWidget {
  final AppState s;
  final WeatherData d;
  const NormalCard({super.key, required this.s, required this.d});

  @override
  Widget build(BuildContext context) {
    final n = s.normal;
    if (n == null || d.daily.isEmpty) return const SizedBox.shrink();
    final pal = SheetPalette.of(context);
    final today = d.daily.first;
    final diff = today.maxC - n.highC;
    final deg = s.tvDelta(diff).abs().round();
    final verdict = deg <= 2
        ? 'About normal for ${DateFormat('MMMM').format(today.date)}'
        : '$deg° ${diff > 0 ? 'warmer' : 'colder'} than a typical '
              '${DateFormat('MMMM d').format(today.date)}';
    final color = deg <= 2
        ? const Color(0xFF22B07D)
        : diff > 0
        ? const Color(0xFFFF8A5B)
        : const Color(0xFF3D9BFF);

    final lo = math.min(today.minC, n.lowC) - 1;
    final hi = math.max(today.maxC, n.highC) + 1;
    Widget bar(String label, double a, double b, Color c) => Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(label, style: TextStyle(color: pal.soft, fontSize: 12)),
        ),
        SizedBox(
          width: 36,
          child: Text(
            s.temp(a),
            textAlign: TextAlign.right,
            style: TextStyle(color: pal.soft, fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (_, box) {
              final w = box.maxWidth;
              final x0 = (a - lo) / (hi - lo) * w;
              final x1 = (b - lo) / (hi - lo) * w;
              return SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: pal.track,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Positioned(
                      left: x0,
                      width: math.max(x1 - x0, 8),
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            s.temp(b),
            style: TextStyle(
              color: pal.ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    return _Card(
      icon: Icons.history_rounded,
      color: color,
      title: 'Compared with normal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            verdict,
            style: TextStyle(
              color: pal.ink,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          bar('Today', today.minC, today.maxC, color),
          const SizedBox(height: 8),
          bar('Normal', n.lowC, n.highC, pal.faint),
          const SizedBox(height: 8),
          Text(
            'Normal = average of the past ${ClimateService.years} years '
            'around this date.',
            style: TextStyle(color: pal.soft, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// "Since you last looked": notable forecast revisions, dismissible.
class ChangesCard extends StatelessWidget {
  final AppState s;
  final WeatherData d;
  const ChangesCard({super.key, required this.s, required this.d});

  @override
  Widget build(BuildContext context) {
    if (s.changes.isEmpty) return const SizedBox.shrink();
    final pal = SheetPalette.of(context);
    IconData icon(ChangeKind k) => switch (k) {
      ChangeKind.warmer => Icons.arrow_upward_rounded,
      ChangeKind.cooler => Icons.arrow_downward_rounded,
      ChangeKind.wetter => Icons.water_drop_rounded,
      ChangeKind.drier => Icons.wb_sunny_outlined,
    };
    Color tint(ChangeKind k) => switch (k) {
      ChangeKind.warmer => const Color(0xFFFF8A5B),
      ChangeKind.cooler => const Color(0xFF3D9BFF),
      ChangeKind.wetter => const Color(0xFF3D9BFF),
      ChangeKind.drier => const Color(0xFFFFB524),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      decoration: BoxDecoration(
        color: _accent.withAlpha(pal.dark ? 45 : 20),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.update_rounded, size: 16, color: _accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'SINCE YOU LAST LOOKED',
                  style: TextStyle(
                    color: pal.soft,
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 18, color: pal.soft),
                onPressed: s.dismissChanges,
              ),
            ],
          ),
          for (final c in s.changes)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon(c.kind), size: 16, color: tint(c.kind)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      describeChange(c, d.current.time, s.temp),
                      style: TextStyle(
                        color: pal.ink,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// The sun's arc today with its current position, the next sunrise /
/// sunset, and how today's daylight compares with yesterday's.
class SunCard extends StatelessWidget {
  final WeatherData d;
  const SunCard({super.key, required this.d});

  @override
  Widget build(BuildContext context) {
    if (d.daily.isEmpty) return const SizedBox.shrink();
    final pal = SheetPalette.of(context);
    final today = d.daily.first;
    final progress = sunProgress(d);
    final next = nextSunEvent(d);
    final change = daylightChange(d);
    final daylight = today.daylight;

    return _Card(
      icon: Icons.wb_twilight_rounded,
      color: const Color(0xFFFFA726),
      title: 'Sun',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 84,
            child: CustomPaint(
              painter: _SunArcPainter(
                progress: progress,
                track: pal.faint,
                ink: pal.ink,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _time(pal, 'Sunrise', today.sunrise),
              // Countdown in the middle; shrinks rather than overflowing on
              // narrow panels and small phones.
              Expanded(
                child: next == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${next.isSunrise ? 'Sunrise' : 'Sunset'} in '
                            '${shortDuration(next.time.difference(d.current.time))}',
                            style: TextStyle(
                              color: pal.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
              ),
              _time(pal, 'Sunset', today.sunset, end: true),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            [
              '${daylight.inHours}h ${daylight.inMinutes % 60}m of daylight',
              if (change != null) daylightChangeText(change).toLowerCase(),
            ].join(' · '),
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.soft, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _time(SheetPalette pal, String label, DateTime t, {bool end = false}) {
    return Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: pal.soft, fontSize: 11)),
        Text(
          DateFormat.jm().format(t),
          style: TextStyle(
            color: pal.ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SunArcPainter extends CustomPainter {
  /// 0 sunrise → 1 sunset; null at night (no sun drawn).
  final double? progress;
  final Color track, ink;
  _SunArcPainter({
    required this.progress,
    required this.track,
    required this.ink,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final base = h - 6;
    // Half-ellipse on the horizon, as wide as the card allows.
    final rx = math.min(w / 2 - 12, 150.0), ry = base - 10;
    final c = Offset(w / 2, base);
    final rect = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);

    canvas.drawLine(
      Offset(c.dx - rx - 8, base),
      Offset(c.dx + rx + 8, base),
      Paint()
        ..color = track
        ..strokeWidth = 1.2,
    );
    final arc = Path()..addArc(rect, math.pi, math.pi);
    // Dashed full path.
    for (final m in arc.computeMetrics()) {
      for (double t = 0; t < m.length; t += 8) {
        canvas.drawPath(
          m.extractPath(t, math.min(t + 4, m.length)),
          Paint()
            ..color = track
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
      final p = progress;
      if (p == null) continue;
      // Travelled part, warm and solid, then the sun itself.
      canvas.drawPath(
        m.extractPath(0, m.length * p),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFFF9E5E), Color(0xFFFFD866)],
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      final pos = m.getTangentForOffset(m.length * p)?.position ?? Offset.zero;
      canvas.drawCircle(
        pos,
        13,
        Paint()..color = const Color(0xFFFFD866).withAlpha(70),
      );
      canvas.drawCircle(pos, 7.5, Paint()..color = const Color(0xFFFFC233));
    }
  }

  @override
  bool shouldRepaint(_SunArcPainter old) =>
      old.progress != progress || old.track != track || old.ink != ink;
}
