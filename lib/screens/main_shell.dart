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

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  SevereEvent? _event;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshEvent();
    _timer = Timer.periodic(
        const Duration(minutes: 15), (_) => _refreshEvent());
    // Fresh installs: ask for location now that the Activity exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().ensureLocation();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Refresh every time the app comes back to the foreground —
      // Sir asked for fresh data each time he returns to it.
      context.read<AppState>().refresh();
      _refreshEvent();
    }
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
