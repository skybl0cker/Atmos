import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/aurora_background.dart';
import '../widgets/daily_list.dart';

/// Full 14-day outlook tab.
class ForecastScreen extends StatelessWidget {
  const ForecastScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final place = s.selected;
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(place == null
              ? '14-Day Forecast'
              : '14-Day · ${place.name}'),
        ),
      body: s.data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: const [
                DailyList(title: '14-day forecast', maxDays: 14),
              ],
            ),
      ),
    );
  }
}
