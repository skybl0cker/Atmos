import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../models/weather.dart';
import '../state/app_state.dart';
import '../utils/hour_entries.dart';
import '../utils/temp_color.dart';
import '../utils/weather_codes.dart';
import '../widgets/art_icon.dart';
import '../widgets/scene.dart';
import '../widgets/scene_page.dart';

const _rain = Color(0xFF3D9BFF);

/// The next 48 hours: a scrolling chart (temperature curve, rain chance,
/// night shading) over an hour-by-hour list with feels-like, wind and
/// humidity, and sunrise / sunset markers in between.
class HourlyScreen extends StatelessWidget {
  const HourlyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data;
    final pal = SheetPalette.of(context);
    return ScenePage(
      title: 'Next 48 Hours',
      subtitle: s.selected?.name,
      sceneHeight: 0.26,
      body: d == null || d.hourly.isEmpty
          ? Center(
              child: Text(
                'No hourly forecast yet.',
                style: TextStyle(color: pal.soft),
              ),
            )
          : _body(context, s, d, pal),
    );
  }

  Widget _body(
    BuildContext context,
    AppState s,
    WeatherData d,
    SheetPalette pal,
  ) {
    final entries = hourEntries(d, count: 48);
    final rows = <Widget>[];
    DateTime? day;
    for (final e in entries) {
      final t = switch (e) {
        HourSlot h => h.hour.time,
        SunSlot u => u.time,
      };
      final date = DateTime(t.year, t.month, t.day);
      if (day == null || date != day) {
        day = date;
        rows.add(SheetLabel(_dayLabel(date, d.current.time)));
      }
      rows.add(switch (e) {
        HourSlot h => _HourRow(s: s, d: d, h: h, pal: pal),
        SunSlot u => _SunRow(u, pal),
      });
    }

    return ListView(
      padding: const EdgeInsets.only(top: 18, bottom: 28),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            decoration: BoxDecoration(
              color: pal.card,
              borderRadius: BorderRadius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            child: HourlyChart(
              hours: d.hourly.take(48).toList(),
              data: d,
              toUnit: s.tv,
            ),
          ),
        ),
        ...rows,
      ],
    );
  }
}

String _dayLabel(DateTime date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final diff = date.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  return DateFormat('EEEE').format(date);
}

/// Scrollable 48-hour chart.
class HourlyChart extends StatelessWidget {
  final List<HourlyPoint> hours;
  final WeatherData data;
  final double Function(double c) toUnit;
  const HourlyChart({
    super.key,
    required this.hours,
    required this.data,
    required this.toUnit,
  });

  static const colW = 46.0;
  static const height = 226.0;

  @override
  Widget build(BuildContext context) {
    final pal = SheetPalette.of(context);
    return SizedBox(
      height: height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: CustomPaint(
          size: Size(hours.length * colW, height),
          painter: _ChartPainter(
            hours: hours,
            shown: [for (final h in hours) toUnit(h.tempC)],
            day: [
              for (var i = 0; i < hours.length; i++)
                i == 0 ? data.current.isDay : data.isDaylight(hours[i].time),
            ],
            now: data.current.time,
            ink: pal.ink,
            soft: pal.soft,
            dark: pal.dark,
          ),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<HourlyPoint> hours;

  /// Temperatures in the user's unit, for the labels.
  final List<double> shown;
  final List<bool> day;
  final DateTime now;
  final Color ink, soft;
  final bool dark;
  _ChartPainter({
    required this.hours,
    required this.shown,
    required this.day,
    required this.now,
    required this.ink,
    required this.soft,
    required this.dark,
  });

  static const _w = HourlyChart.colW;
  // Vertical bands of the chart.
  static const _curveTop = 46.0, _curveH = 78.0;
  static const _barBase = 186.0, _barMax = 36.0;
  static const _hourY = 200.0;

  void _text(
    Canvas canvas,
    String s,
    Offset center, {
    required Color color,
    double size = 11,
    FontWeight weight = FontWeight.w500,
    bool left = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          fontFamily: 'Poppins',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      left ? center : center - Offset(tp.width / 2, tp.height / 2),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = hours.length;
    if (n == 0) return;

    // Night hours get a soft shade so the day/night rhythm reads at once.
    final shade = Paint()..color = (dark ? Colors.black : ink).withAlpha(16);
    for (var i = 0; i < n; i++) {
      if (!day[i]) {
        canvas.drawRect(Rect.fromLTWH(i * _w, 0, _w, size.height), shade);
      }
    }

    // Day labels, with a divider at each midnight.
    final rule = Paint()
      ..color = soft.withAlpha(70)
      ..strokeWidth = 1;
    for (var i = 0; i < n; i++) {
      final t = hours[i].time;
      if (i == 0 || t.hour == 0) {
        if (i > 0) {
          canvas.drawLine(
            Offset(i * _w, 8),
            Offset(i * _w, size.height - 8),
            rule,
          );
        }
        final today = DateTime(now.year, now.month, now.day);
        final diff = DateTime(t.year, t.month, t.day).difference(today).inDays;
        _text(
          canvas,
          diff == 0
              ? 'Today'
              : diff == 1
              ? 'Tomorrow'
              : DateFormat('EEEE').format(t),
          Offset(i * _w + 10, 10),
          color: soft,
          size: 11,
          weight: FontWeight.w600,
          left: true,
        );
      }
    }

    // Temperature curve, with "feels like" as a dashed line on the same
    // scale (when the forecast has it) so wind chill / humidity show as the
    // gap between the two.
    final temps = [for (final h in hours) h.tempC];
    final feels = hours.every((h) => h.feelsC != null)
        ? [for (final h in hours) h.feelsC!]
        : null;
    final all = [...temps, ...?feels];
    final lo = all.reduce(math.min), hi = all.reduce(math.max);
    final range = math.max(hi - lo, 1.0);
    List<Offset> pointsFor(List<double> v) => [
      for (var i = 0; i < n; i++)
        Offset(
          i * _w + _w / 2,
          _curveTop + (1 - (v[i] - lo) / range) * _curveH,
        ),
    ];
    Path smooth(List<Offset> p) {
      final path = Path()..moveTo(p.first.dx, p.first.dy);
      for (var i = 0; i < p.length - 1; i++) {
        final p0 = i == 0 ? p[i] : p[i - 1];
        final p1 = p[i], p2 = p[i + 1];
        final p3 = i + 2 < p.length ? p[i + 2] : p2;
        final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
      }
      return path;
    }

    final pts = pointsFor(temps);
    final path = smooth(pts);
    // Only worth drawing when feels-like actually differs somewhere.
    final feelsDiffers =
        feels != null &&
        [for (var i = 0; i < n; i++) (feels[i] - temps[i]).abs()]
            .any((g) => g >= 1.5);
    if (feelsDiffers) {
      final dashed = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = soft.withAlpha(170);
      for (final m in smooth(pointsFor(feels)).computeMetrics()) {
        for (double t = 0; t < m.length; t += 9) {
          canvas.drawPath(m.extractPath(t, math.min(t + 5, m.length)), dashed);
        }
      }
      // Tiny legend, top right of the visible start.
      _text(
        canvas,
        '— temp   - - feels like',
        Offset(n * _w - 140, 10),
        color: soft,
        size: 10,
        left: true,
      );
    }
    final bounds = Offset.zero & size;
    // The line takes each hour's color from the same cold→hot ramp as the
    // daily range bars.
    final ramp = n == 1
        ? null
        : LinearGradient(colors: [for (final c in temps) tempColor(c)])
              .createShader(bounds);
    final fill = Path.from(path)
      ..lineTo(pts.last.dx, _curveTop + _curveH + 16)
      ..lineTo(pts.first.dx, _curveTop + _curveH + 16)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ink.withAlpha(dark ? 34 : 20), ink.withAlpha(0)],
        ).createShader(Rect.fromLTWH(0, _curveTop, size.width, _curveH + 16)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..shader = ramp
        ..color = tempColor(temps.first),
    );

    final iHi = temps.indexOf(hi), iLo = temps.indexOf(lo);
    for (var i = 0; i < n; i++) {
      final first = i == 0;
      // Label every third hour, plus the high and the low.
      final labelled = first || i % 3 == 0 || i == iHi || i == iLo;
      if (!labelled) continue;
      canvas.drawCircle(
        pts[i],
        first ? 5 : 3.5,
        Paint()..color = dark ? const Color(0xFF1C1838) : Colors.white,
      );
      canvas.drawCircle(
        pts[i],
        first ? 5 : 3.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = tempColor(temps[i]),
      );
      _text(
        canvas,
        '${shown[i].round()}°',
        pts[i] - const Offset(-2, 15),
        color: ink,
        size: first ? 13 : 12,
        weight: first ? FontWeight.w600 : FontWeight.w500,
      );
    }

    // Rain chance bars.
    for (var i = 0; i < n; i++) {
      final p = hours[i].precipProb.clamp(0, 100) / 100;
      final x = i * _w + _w / 2;
      if (p <= 0) {
        canvas.drawLine(
          Offset(x - 7, _barBase),
          Offset(x + 7, _barBase),
          Paint()
            ..color = soft.withAlpha(60)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
        continue;
      }
      final hgt = math.max(3.0, _barMax * p);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 8, _barBase - hgt, 16, hgt),
          const Radius.circular(4),
        ),
        Paint()..color = _rain.withAlpha((90 + 165 * p).round()),
      );
      if (hours[i].precipProb >= 20) {
        _text(
          canvas,
          '${hours[i].precipProb}%',
          Offset(x, _barBase - hgt - 8),
          color: _rain,
          size: 9.5,
          weight: FontWeight.w600,
        );
      }
    }

    // Hour labels.
    for (var i = 0; i < n; i += 3) {
      _text(
        canvas,
        i == 0 ? 'Now' : DateFormat('ha').format(hours[i].time).toLowerCase(),
        Offset(i * _w + _w / 2, _hourY + 8),
        color: i == 0 ? ink : soft,
        size: 11,
        weight: i == 0 ? FontWeight.w600 : FontWeight.w400,
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.hours != hours ||
      old.dark != dark ||
      old.shown.first != shown.first ||
      old.ink != ink;
}

class _HourRow extends StatelessWidget {
  final AppState s;
  final WeatherData d;
  final HourSlot h;
  final SheetPalette pal;
  const _HourRow({
    required this.s,
    required this.d,
    required this.h,
    required this.pal,
  });

  @override
  Widget build(BuildContext context) {
    final p = h.hour;
    final now = h.index == 0;
    final daytime = now ? d.current.isDay : d.isDaylight(p.time);
    final details = <String>[
      if (p.humidity != null) '${p.humidity}% humidity',
      if (daytime && (p.uv ?? 0) >= 1) 'UV ${p.uv!.round()}',
      if ((p.gustKmh ?? 0) >= (p.windKmh ?? 0) + 15)
        'gusts ${s.wind(p.gustKmh!)}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
        decoration: BoxDecoration(
          color: now
              ? const Color(0xFF6C63FF).withAlpha(pal.dark ? 50 : 22)
              : pal.card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 54,
              child: Text(
                now ? 'Now' : DateFormat('h a').format(p.time),
                style: TextStyle(
                  color: pal.ink,
                  fontSize: 13,
                  fontWeight: now ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            ArtIcon(p.code, day: daytime, size: 30, onDark: pal.dark),
            const SizedBox(width: 10),
            SizedBox(
              width: 40,
              child: Text(
                s.temp(p.tempC),
                style: TextStyle(
                  color: pal.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.feelsC == null
                        ? describe(p.code)
                        : 'Feels ${s.temp(p.feelsC!)} · ${describe(p.code)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: pal.ink, fontSize: 12),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: pal.soft, fontSize: 11),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (p.precipProb >= 10)
                  Text(
                    '${p.precipProb}%',
                    style: const TextStyle(
                      color: _rain,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (p.windKmh != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (p.windDir != null)
                        // Points the way the wind is blowing (from → to).
                        Transform.rotate(
                          angle: (p.windDir! + 180) * math.pi / 180,
                          child: Icon(
                            Icons.navigation_rounded,
                            size: 12,
                            color: pal.soft,
                          ),
                        ),
                      const SizedBox(width: 3),
                      Text(
                        s.wind(p.windKmh!),
                        style: TextStyle(color: pal.soft, fontSize: 11),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SunRow extends StatelessWidget {
  final SunSlot e;
  final SheetPalette pal;
  const _SunRow(this.e, this.pal);

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFFFA726);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
      child: Row(
        children: [
          Expanded(child: Divider(color: amber.withAlpha(90), height: 1)),
          const SizedBox(width: 10),
          const Icon(Icons.wb_twilight_rounded, color: amber, size: 18),
          const SizedBox(width: 6),
          Text(
            '${e.isSunrise ? 'Sunrise' : 'Sunset'} · ${DateFormat.jm().format(e.time)}',
            style: TextStyle(
              color: pal.soft,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: amber.withAlpha(90), height: 1)),
        ],
      ),
    );
  }
}
