import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/severe_event_service.dart';
import '../state/app_state.dart';
import 'home_screen.dart';

/// Bento home shell: no tab bar. The home grid's tiles dive into the full
/// Radar / Forecast / Event screens via Navigator. The headline severe
/// event is polled here so the home's event tile stays live.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
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
      // The event tile keeps its last known state; EventScreen retries itself.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Warm the weather state so the bento has data.
    context.watch<AppState>();
    return HomeScreen(event: _event);
  }
}
