import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class WeatherBackground extends StatefulWidget {
  final int code;
  final bool isDay;
  final Widget child;

  /// Paint drifting cloud blobs. Off when layered over illustrations that
  /// already have their own clouds.
  final bool clouds;

  const WeatherBackground({
    super.key,
    required this.code,
    required this.isDay,
    required this.child,
    this.clouds = true,
  });

  @override
  State<WeatherBackground> createState() => _WeatherBackgroundState();
}

class _WeatherBackgroundState extends State<WeatherBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  final _particles = _Particles();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _clock.value = d.inMicroseconds / 1e6)
      ..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the system "remove animations" accessibility setting.
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced && _ticker.isActive) {
      _ticker.stop();
    } else if (!reduced && !_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final full = _specFor(widget.code, widget.isDay);
    final spec = widget.clouds
        ? full
        : _Spec(
            rain: full.rain,
            snow: full.snow,
            stars: full.stars,
            lightning: full.lightning,
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(painter: _FxPainter(_clock, spec, _particles)),
          ),
        ),
        widget.child,
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Spec {
  final int rain;
  final int snow;
  final int clouds;
  final bool stars;
  final bool lightning;
  final bool fog;
  final double cloudAlpha;
  final Color cloudColor;

  const _Spec({
    this.rain = 0,
    this.snow = 0,
    this.clouds = 0,
    this.stars = false,
    this.lightning = false,
    this.fog = false,
    this.cloudAlpha = 0.25,
    this.cloudColor = Colors.white,
  });
}

_Spec _specFor(int code, bool day) {
  if (code < 0) return const _Spec();
  if (code == 0 || code == 1) {
    return day
        ? const _Spec(clouds: 2, cloudAlpha: 0.18)
        : const _Spec(stars: true, clouds: 1, cloudAlpha: 0.08);
  }
  if (code == 2) {
    return day
        ? const _Spec(clouds: 4, cloudAlpha: 0.3)
        : const _Spec(stars: true, clouds: 3, cloudAlpha: 0.15);
  }
  if (code == 3) {
    return const _Spec(
      clouds: 6,
      cloudAlpha: 0.32,
      cloudColor: Color(0xFFDDE3EA),
    );
  }
  if (code == 45 || code == 48) {
    return const _Spec(clouds: 6, fog: true, cloudAlpha: 0.28);
  }
  if (code >= 51 && code <= 57) {
    return const _Spec(rain: 45, clouds: 5, cloudColor: Color(0xFFB8C2CF));
  }
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) {
    final heavy = code == 65 || code == 67 || code == 82;
    return _Spec(
      rain: heavy ? 160 : 100,
      clouds: 6,
      cloudColor: const Color(0xFFB8C2CF),
    );
  }
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
    return const _Spec(snow: 70, clouds: 4, cloudAlpha: 0.22);
  }
  if (code >= 95) {
    return const _Spec(
      rain: 150,
      clouds: 6,
      lightning: true,
      cloudAlpha: 0.4,
      cloudColor: Color(0xFF6B7380),
    );
  }
  return const _Spec(clouds: 3);
}

/// Four random numbers in [0,1); each effect interprets them its own way.
class _P {
  final double a, b, c, d;
  const _P(this.a, this.b, this.c, this.d);
}

class _Particles {
  static List<_P> _gen(int n, math.Random r) => List.generate(
    n,
    (_) => _P(r.nextDouble(), r.nextDouble(), r.nextDouble(), r.nextDouble()),
    growable: false,
  );

  final rain = _gen(160, math.Random(1));
  final snow = _gen(70, math.Random(2));
  final stars = _gen(70, math.Random(3));
  final clouds = _gen(6, math.Random(4));
}

Color _c(double alpha, [int r = 255, int g = 255, int b = 255]) =>
    Color.fromRGBO(r, g, b, alpha.clamp(0.0, 1.0).toDouble());

class _FxPainter extends CustomPainter {
  final ValueNotifier<double> clock;
  final _Spec spec;
  final _Particles p;

  _FxPainter(this.clock, this.spec, this.p) : super(repaint: clock);

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final w = size.width;
    final h = size.height;

    if (spec.stars) _paintStars(canvas, t, w, h);
    if (spec.clouds > 0) _paintClouds(canvas, t, w, h);
    if (spec.snow > 0) _paintSnow(canvas, t, w, h);
    if (spec.rain > 0) _paintRain(canvas, t, w, h);
    if (spec.lightning) _paintLightning(canvas, t, size);
  }

  void _paintStars(Canvas canvas, double t, double w, double h) {
    final paint = Paint();
    for (final s in p.stars) {
      final twinkle = 0.5 + 0.5 * math.sin(t * (1 + s.c * 2) + s.d * 6.283);
      paint.color = _c(0.25 + 0.65 * twinkle);
      canvas.drawCircle(Offset(s.a * w, s.b * h * 0.6), 0.6 + s.c * 1.4, paint);
    }
  }

  void _paintClouds(Canvas canvas, double t, double w, double h) {
    final paint = Paint()
      ..color = spec.cloudColor.withValues(
        alpha: spec.cloudAlpha.clamp(0.0, 1.0).toDouble(),
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    final fogScale = spec.fog ? 2.2 : 1.0;

    for (var i = 0; i < spec.clouds && i < p.clouds.length; i++) {
      final c = p.clouds[i];
      final speed = 0.004 + c.c * 0.008;
      final x = ((c.a + t * speed) % 1.6 - 0.3) * w;
      final y = (spec.fog ? 0.25 + c.b * 0.6 : 0.03 + c.b * 0.4) * h;
      final cw = 220 * (0.7 + c.d * 0.8) * fogScale;
      final ch = 80 * (0.7 + c.d * 0.8) * (spec.fog ? 1.4 : 1.0);

      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: cw, height: ch),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x - cw * 0.3, y + ch * 0.15),
          width: cw * 0.7,
          height: ch * 0.8,
        ),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x + cw * 0.3, y + ch * 0.1),
          width: cw * 0.7,
          height: ch * 0.75,
        ),
        paint,
      );
    }
  }

  void _paintRain(Canvas canvas, double t, double w, double h) {
    final paint = Paint()
      ..color = _c(0.4, 200, 220, 255)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < spec.rain && i < p.rain.length; i++) {
      final d = p.rain[i];
      final fall = (d.b + t * (0.7 + d.c * 0.8)) % 1;
      final len = 10 + d.d * 16;
      final y = fall * (h + 40) - 20;
      final x = (d.a * w + fall * 40) % w;
      canvas.drawLine(Offset(x, y), Offset(x - len * 0.25, y - len), paint);
    }
  }

  void _paintSnow(Canvas canvas, double t, double w, double h) {
    final paint = Paint()..color = _c(0.85);
    for (var i = 0; i < spec.snow && i < p.snow.length; i++) {
      final f = p.snow[i];
      final fall = (f.b + t * (0.05 + f.c * 0.08)) % 1;
      final y = fall * (h + 20) - 10;
      final sway = math.sin(t * 0.8 + f.b * 6.283) * (10 + f.a * 20);
      canvas.drawCircle(Offset(f.a * w + sway, y), 1.5 + f.d * 2.5, paint);
    }
  }

  void _paintLightning(Canvas canvas, double t, Size size) {
    final a = t % 9.7;
    final b = (t + 4.3) % 13.1;
    var alpha = 0.0;
    if (a < 0.12) alpha = 1 - a / 0.12;
    if (a > 0.3 && a < 0.42) alpha = 0.7 * (1 - (a - 0.3) / 0.12);
    if (b < 0.1) alpha = math.max(alpha, 0.8 * (1 - b / 0.1));
    if (alpha > 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = _c(alpha * 0.35));
    }
  }

  @override
  bool shouldRepaint(_FxPainter old) => true;
}
