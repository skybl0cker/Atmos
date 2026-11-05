import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A small moon disc lit to match the phase (0 new → 0.5 full → 1 new),
/// lit on the right while waxing and the left while waning.
class MoonIcon extends StatelessWidget {
  final double phase;
  final double size;
  final Color shadow;
  const MoonIcon(
      {super.key, required this.phase, this.size = 28, required this.shadow});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MoonPainter(phase, shadow)),
      );
}

class _MoonPainter extends CustomPainter {
  final double phase;
  final Color shadow;
  _MoonPainter(this.phase, this.shadow);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 1;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()..color = shadow);

    final waxing = phase < 0.5;
    // Terminator half-width: r at new, 0 at quarters, -r at full.
    final k = math.cos(2 * math.pi * phase);
    final lit = Path()..moveTo(c.dx, c.dy - r);
    // Outer limb on the lit side, top → bottom.
    lit.arcTo(rect, -math.pi / 2, waxing ? math.pi : -math.pi, false);
    // Back up along the terminator, bottom → top.
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final t = math.pi * i / steps;
      final x = r * k * math.sin(t);
      lit.lineTo(c.dx + (waxing ? x : -x), c.dy + r * math.cos(t));
    }
    lit.close();
    canvas.drawPath(lit, Paint()..color = const Color(0xFFFFE39A));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x33000000));
  }

  @override
  bool shouldRepaint(_MoonPainter old) =>
      old.phase != phase || old.shadow != shadow;
}
