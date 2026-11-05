import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/weather_codes.dart';

/// Hand-drawn style condition icons: a soft golden sun with fine rays,
/// white outlined clouds, slanted blue rain, a crescent moon. Painted, so
/// they stay crisp at any size and can adapt to light / dark surfaces.
class ArtIcon extends StatelessWidget {
  final int code;
  final bool day;
  final double size;

  /// Draw for a dark surface (lighter outline, deeper cloud fill).
  final bool onDark;
  const ArtIcon(
    this.code, {
    super.key,
    required this.day,
    this.size = 36,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ArtPainter(code, day, onDark)),
    );
  }
}

enum _Kind { clear, partly, cloudy, fog, rain, snow, storm }

_Kind _kindFor(int code) {
  if (code == 0 || code == 1) return _Kind.clear;
  if (code == 2) return _Kind.partly;
  if (code == 3) return _Kind.cloudy;
  if (code == 45 || code == 48) return _Kind.fog;
  if (code >= 95) return _Kind.storm;
  if (isSnowCode(code)) return _Kind.snow;
  if (isRainCode(code)) return _Kind.rain;
  return _Kind.cloudy;
}

class _ArtPainter extends CustomPainter {
  final int code;
  final bool day;
  final bool onDark;
  _ArtPainter(this.code, this.day, this.onDark);

  static const _sunA = Color(0xFFFFD866);
  static const _sunB = Color(0xFFFFB524);
  static const _drop = Color(0xFF4AA8FF);

  Color get _ink => onDark ? const Color(0xFFE9E4FF) : const Color(0xFF2B2346);
  Color get _cloudFill => onDark ? const Color(0xFF3A3166) : Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    switch (_kindFor(code)) {
      case _Kind.clear:
        day
            ? _sun(canvas, Offset(s * .5, s * .5), s * .27, s)
            : _moon(canvas, Offset(s * .5, s * .5), s * .3);
      case _Kind.partly:
        day
            ? _sun(canvas, Offset(s * .38, s * .36), s * .2, s)
            : _moon(canvas, Offset(s * .38, s * .34), s * .22);
        _cloud(canvas, s, dx: .08, dy: .12, scale: .82);
      case _Kind.cloudy:
        _cloud(canvas, s, dx: .1, dy: -.06, scale: .62, faded: true);
        _cloud(canvas, s, dx: -.02, dy: .06, scale: .9);
      case _Kind.fog:
        _cloud(canvas, s, dx: 0, dy: -.1, scale: .85);
        final p = Paint()
          ..color = _ink.withAlpha(150)
          ..strokeWidth = s * .05
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(s * .2, s * .78), Offset(s * .72, s * .78), p);
        canvas.drawLine(Offset(s * .34, s * .9), Offset(s * .84, s * .9), p);
      case _Kind.rain:
        _cloud(canvas, s, dx: 0, dy: -.1, scale: .9);
        final p = Paint()
          ..color = _drop
          ..strokeWidth = s * .045
          ..strokeCap = StrokeCap.round;
        final heavy = code == 65 || code == 67 || code == 82;
        final xs = heavy ? [.3, .42, .54, .66] : [.34, .5, .66];
        for (var i = 0; i < xs.length; i++) {
          final x = xs[i] * s, y = (i.isEven ? .72 : .8) * s;
          canvas.drawLine(Offset(x, y), Offset(x - s * .05, y + s * .12), p);
        }
      case _Kind.snow:
        _cloud(canvas, s, dx: 0, dy: -.1, scale: .9);
        final p = Paint()..color = const Color(0xFF8FD3FF);
        for (final o in const [
          Offset(.34, .78),
          Offset(.5, .88),
          Offset(.66, .78),
          Offset(.42, .95),
          Offset(.6, .97),
        ]) {
          canvas.drawCircle(o * s, s * .035, p);
        }
      case _Kind.storm:
        _cloud(canvas, s, dx: 0, dy: -.12, scale: .9);
        final bolt = Path()
          ..moveTo(s * .52, s * .6)
          ..lineTo(s * .38, s * .8)
          ..lineTo(s * .5, s * .8)
          ..lineTo(s * .42, s * .98)
          ..lineTo(s * .66, s * .72)
          ..lineTo(s * .53, s * .72)
          ..lineTo(s * .6, s * .6)
          ..close();
        canvas.drawPath(bolt, Paint()..color = _sunB);
    }
  }

  void _sun(Canvas canvas, Offset c, double r, double s) {
    canvas.drawCircle(c, r * 1.5, Paint()..color = _sunA.withAlpha(50));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.35),
          colors: [_sunA, _sunB],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Fine dotted rays, like a pencil sketch.
    final ray = Paint()
      ..color = _sunB.withAlpha(200)
      ..strokeWidth = math.max(1, s * .03)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final d = Offset(math.cos(a), math.sin(a));
      final long = i.isEven;
      canvas.drawLine(c + d * r * 1.42, c + d * r * (long ? 1.72 : 1.56), ray);
    }
  }

  void _moon(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(
      c,
      r * 1.45,
      Paint()..color = const Color(0xFFFFE9A8).withAlpha(45),
    );
    canvas.saveLayer(Rect.fromCircle(center: c, radius: r * 1.6), Paint());
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFFFE39A));
    canvas.drawCircle(
      c + Offset(r * .45, -r * .35),
      r * .85,
      Paint()..blendMode = BlendMode.dstOut,
    );
    canvas.restore();
  }

  /// Puffy outlined cloud. [dx]/[dy] shift it (fractions of the icon),
  /// [scale] shrinks it around the icon centre.
  void _cloud(
    Canvas canvas,
    double s, {
    double dx = 0,
    double dy = 0,
    double scale = 1,
    bool faded = false,
  }) {
    Offset p(double x, double y) => Offset(
      (0.5 + (x - 0.5) * scale + dx) * s,
      (0.5 + (y - 0.5) * scale + dy) * s,
    );
    double r(double v) => v * scale * s;

    var path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(p(.14, .5), p(.88, .76)),
          Radius.circular(r(.13)),
        ),
      );
    for (final (x, y, rad) in const [
      (.34, .52, .17),
      (.55, .42, .23),
      (.75, .55, .15),
    ]) {
      path = Path.combine(
        PathOperation.union,
        path,
        Path()..addOval(Rect.fromCircle(center: p(x, y), radius: r(rad))),
      );
    }
    canvas.drawPath(
      path,
      Paint()..color = faded ? _cloudFill.withAlpha(200) : _cloudFill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, s * .045)
        ..strokeJoin = StrokeJoin.round
        ..color = faded ? _ink.withAlpha(110) : _ink,
    );
  }

  @override
  bool shouldRepaint(_ArtPainter old) =>
      old.code != code || old.day != day || old.onDark != onDark;
}
