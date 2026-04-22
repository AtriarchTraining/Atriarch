import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'data/drill_log_repository.dart';
import 'data/hive_bootstrap.dart';
import 'data/preferences_repository.dart';
import 'data/session_repository.dart';
import 'services/audio_service.dart';
import 'state/app_state.dart';
import 'theme/atriarch_theme.dart';
import 'theme/theme_controller.dart';
import 'screens/device_discovery_screen.dart';
import 'screens/onboarding/onboarding_flow.dart';

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

  // Gate 2 #19: first-run onboarding gate. Read the flag synchronously so
  // the MaterialApp home can branch on it without a loading flicker.
  final onboardingComplete =
      await preferences.getSetting<bool>('onboarding_complete') ?? false;

  final themeController = ThemeController(preferences: preferences);
  await themeController.init();

  // Gate 2 #15: ready-audio chime. Session-long lifecycle; Flutter disposes
  // on process exit. init() is best-effort — audio-session + asset preload
  // failures are logged and swallowed.
  final audio = AudioService();
  await audio.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppState(
            preferences: preferences,
            sessions: sessions,
            drillLogs: drillLogs,
            audio: audio,
          ),
        ),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
      ],
      child: AtriarchApp(onboardingComplete: onboardingComplete),
    ),
  );
}

class AtriarchApp extends StatelessWidget {
  final bool onboardingComplete;

  const AtriarchApp({super.key, required this.onboardingComplete});

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
          home: onboardingComplete
              ? StreamBuilder<BluetoothAdapterState>(
                  stream: FlutterBluePlus.adapterState,
                  initialData: BluetoothAdapterState.unknown,
                  builder: (context, snapshot) {
                    if (snapshot.data == BluetoothAdapterState.on) {
                      return const DeviceDiscoveryScreen();
                    }
                    return const BluetoothOffScreen();
                  },
                )
              : const OnboardingFlow(),
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
