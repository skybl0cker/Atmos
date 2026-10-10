import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'screens/main_shell.dart';
import 'services/background_dispatcher.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Closed-app background work: Android only. iOS background execution can't
  // do this without a push server, and the web build has no background at
  // all. One dispatcher handles both the rain check and the severe-alert
  // check (Workmanager allows a single entry point).
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await Workmanager().initialize(atmosDispatcher);
    await Workmanager().registerPeriodicTask(
      'atmos-rain-check',
      'rainCheckTask',
      frequency: const Duration(minutes: 30),
      constraints: Constraints(networkType: NetworkType.connected),
    );
    await Workmanager().registerPeriodicTask(
      'atmos-alert-check',
      'alertCheckTask',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  final state = AppState();
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const AtmosApp()));
}

/// Atmos purple — sampled from the app icon.
const _atmosPurple = Color(0xFF7C4DFF);

class AtmosApp extends StatelessWidget {
  const AtmosApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppState, ThemeMode>((s) => s.themeMode);
    return MaterialApp(
      title: 'Atmos',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _atmosPurple,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _atmosPurple,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF120E24),
        cardColor: const Color(0xFF1D1540),
      ),
      home: const MainShell(),
    );
  }
}
