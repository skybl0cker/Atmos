import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'screens/main_shell.dart';
import 'services/background_rain.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Closed-app rain checks: Android only. iOS background execution can't do
  // this without a push server, and the web build has no background at all.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await Workmanager().initialize(rainCheckDispatcher);
    await Workmanager().registerPeriodicTask(
      'skycast-rain-check',
      'rainCheckTask',
      frequency: const Duration(minutes: 30),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  final state = AppState();
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const SkyCastApp()));
}

class SkyCastApp extends StatelessWidget {
  const SkyCastApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppState, ThemeMode>((s) => s.themeMode);
    return MaterialApp(
      title: 'SkyCast',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
      ),
      home: const MainShell(),
    );
  }
}
