import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'data/drill_log_repository.dart';
import 'data/hive_bootstrap.dart';
import 'data/preferences_repository.dart';
import 'data/session_repository.dart';
import 'state/app_state.dart';
import 'theme/atriarch_theme.dart';
import 'theme/theme_controller.dart';
import 'screens/device_discovery_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHive();

  final preferences = PreferencesRepository();
  final sessions = SessionRepository();
  final drillLogs = DrillLogRepository();

  await Future.wait([
    preferences.init(),
    sessions.init(),
    drillLogs.init(),
  ]);
  // On cold start, begin (or roll over) the current session per §4.E.
  await sessions.beginSessionIfNeeded();

  final themeController = ThemeController(preferences: preferences);
  await themeController.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppState(
            preferences: preferences,
            sessions: sessions,
            drillLogs: drillLogs,
          ),
        ),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
      ],
      child: const AtriarchApp(),
    ),
  );
}

class AtriarchApp extends StatelessWidget {
  const AtriarchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeController>(
      builder: (context, ctrl, _) {
        // Respect Reduce Motion for the theme cross-fade.
        final disableAnimations =
            MediaQueryData.fromView(View.of(context)).disableAnimations;
        final duration = disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 400);
        return MaterialApp(
          title: 'Atriarch',
          theme: buildAtriarchLightTheme(),
          darkTheme: buildAtriarchDarkTheme(),
          themeMode: ctrl.themeMode,
          themeAnimationDuration: duration,
          themeAnimationCurve: Curves.easeInOut,
          home: StreamBuilder<BluetoothAdapterState>(
            stream: FlutterBluePlus.adapterState,
            initialData: BluetoothAdapterState.unknown,
            builder: (context, snapshot) {
              if (snapshot.data == BluetoothAdapterState.on) {
                return const DeviceDiscoveryScreen();
              }
              return const BluetoothOffScreen();
            },
          ),
        );
      },
    );
  }
}

class BluetoothOffScreen extends StatelessWidget {
  const BluetoothOffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bluetooth_disabled,
              size: 100,
              color: tokens.statusOffline,
            ),
            const SizedBox(height: 16),
            Text(
              'Please enable Bluetooth',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
