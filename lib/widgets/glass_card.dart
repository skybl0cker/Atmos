import 'package:flutter/material.dart';
import 'aurora_background.dart';

/// Titled frosted-glass card floating above the aurora.
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
    return FrostPanel(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 15, color: Colors.white70),
            const SizedBox(width: 6),
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
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
