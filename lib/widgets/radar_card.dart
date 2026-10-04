import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/radar_screen.dart';
import '../state/app_state.dart';
import 'glass_card.dart';

class RadarCard extends StatelessWidget {
  const RadarCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final place = s.selected;
    if (place == null) return const SizedBox.shrink();
    final minutely = s.data?.minutely ?? const [];
    final windKmh = s.data?.steeringWindKmh ?? 0;
    final windDir = s.data?.steeringWindDir ?? 0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RadarScreen(
                place: place,
                minutely: minutely,
                windKmh: windKmh,
                windDir: windDir)),
      ),
      child: const GlassCard(
        title: 'Radar',
        icon: Icons.radar,
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Live radar with +30/+60 min forecast frames and a 4-hour rain outlook',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}
