import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

/// Deep-purple aurora background: a near-black violet base with three
/// slowly drifting radial color blobs (violet, magenta, indigo).
/// Panels float above it with frosted glass.
class AuroraBackground extends StatefulWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF150E33), Color(0xFF0B0721)],
        ),
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value * 2 * math.pi;
          return CustomPaint(
            painter: _AuroraPainter(t),
            child: widget.child,
          );
        },
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  _AuroraPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final blobs = [
      _Blob(
        color: const Color(0xFF7C4DFF),
        cx: 0.22 + 0.08 * math.sin(t * 0.9),
        cy: 0.12 + 0.05 * math.cos(t * 0.7),
        r: 0.55,
        alpha: 0.34,
      ),
      _Blob(
        color: const Color(0xFFE040FB),
        cx: 0.85 + 0.07 * math.cos(t * 0.6 + 1.3),
        cy: 0.38 + 0.06 * math.sin(t * 0.8 + 0.5),
        r: 0.48,
        alpha: 0.22,
      ),
      _Blob(
        color: const Color(0xFF3949AB),
        cx: 0.45 + 0.09 * math.sin(t * 0.5 + 2.1),
        cy: 0.82 + 0.05 * math.cos(t * 0.65 + 1.0),
        r: 0.6,
        alpha: 0.3,
      ),
    ];
    for (final b in blobs) {
      final center = Offset(b.cx * size.width, b.cy * size.height);
      final radius = b.r * math.max(size.width, size.height);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            b.color.withAlpha((b.alpha * 255).round()),
            b.color.withAlpha(0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}

class _Blob {
  final Color color;
  final double cx, cy, r, alpha;
  const _Blob(
      {required this.color,
      required this.cx,
      required this.cy,
      required this.r,
      required this.alpha});
}

/// Frosted glass panel that floats above [AuroraBackground].
class FrostPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const FrostPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(26),
              borderRadius: BorderRadius.circular(24),
              border:
                  Border.all(color: Colors.white.withAlpha(45), width: 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
