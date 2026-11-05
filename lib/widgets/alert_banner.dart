import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/alerts_screen.dart';
import '../state/app_state.dart';

class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<AppState>().alerts;
    if (alerts.isEmpty) return const SizedBox.shrink();

    final worst = alerts.reduce((a, b) => a.isSevere ? a : b);
    final color = worst.isSevere
        ? const Color(0xFFD32F2F)
        : const Color(0xFFF57C00);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AlertsScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withAlpha(230),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alerts.length == 1
                            ? worst.event
                            : '${worst.event} + ${alerts.length - 1} more',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Tap for details',
                        style: TextStyle(
                          color: Colors.white.withAlpha(220),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
