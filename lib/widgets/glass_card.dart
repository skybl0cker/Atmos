import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const GlassCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1542).withAlpha(200),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF7C4DFF).withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 15, color: Colors.white70),
            const SizedBox(width: 6),
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.8,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
