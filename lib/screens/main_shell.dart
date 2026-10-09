import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/severe_event_service.dart';
import '../state/app_state.dart';
import 'event_screen.dart';
import 'forecast_screen.dart';
import 'home_screen.dart';
import 'radar_screen.dart';

/// Bottom navigation: Home, 14-day Forecast, Radar, and a dynamic 4th tab
/// whose icon and label follow the current headline severe weather event
/// nationwide (hurricane, tornado outbreak, ...), falling back to "Alerts".
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  SevereEvent? _event;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refreshEvent();
    _timer = Timer.periodic(
        const Duration(minutes: 15), (_) => _refreshEvent());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshEvent() async {
    try {
      final e = await SevereEventService.current();
      if (mounted) setState(() => _event = e);
    } catch (_) {
      // Tab keeps its last known state; the event screen retries itself.
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final place = s.selected;
    final SevereEvent? event = _event;
    final eventActive =
        event != null && event.kind != SevereKind.none;
    final Color? eventColor = eventActive ? event.color : null;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const HomeScreen(),
          const ForecastScreen(),
          place == null
              ? const Center(child: CircularProgressIndicator())
              : RadarScreen(
                  key: ValueKey(place.key),
                  place: place,
                  minutely: s.data?.minutely ?? const [],
                  windKmh: s.data?.steeringWindKmh ?? 0,
                  windDir: s.data?.steeringWindDir ?? 0,
                ),
          const EventScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: _index == 3 ? eventColor : null,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            activeIcon: Icon(Icons.calendar_month),
            label: 'Forecast',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.radar_outlined),
            activeIcon: Icon(Icons.radar),
            label: 'Radar',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              event?.tabIcon ?? Icons.notifications_outlined,
              color: eventColor,
            ),
            activeIcon: Icon(
              event?.tabIcon ?? Icons.notifications,
              color: eventColor,
            ),
            label: event?.tabLabel ?? 'Alerts',
          ),
        ],
      ),
    );
  }
}
