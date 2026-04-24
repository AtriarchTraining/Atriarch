import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db/database_helper.dart';
import 'repositories/drill_template_repository.dart';
import 'repositories/session_repository.dart';
import 'repositories/shooter_repository.dart';
import 'screens/device_discovery_screen.dart';
import 'screens/home_screen.dart';
import 'services/audio_service.dart';
import 'services/orphan_recovery.dart';
import 'services/preferences_repository.dart';
import 'services/range_session_view.dart';
import 'services/tts_port.dart';
import 'state/app_state.dart';
import 'state/shooter_state.dart';
import 'theme/atriarch_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Web preview bypass: no sqflite on web, no platform channels.
  if (kIsWeb) {
    runApp(const _WebPreviewApp());
    return;
  }

  final db = await DatabaseHelper.instance();
  final prefs = await SharedPreferences.getInstance();

  final preferences = PreferencesRepository(prefs);
  final sessionRepo = SessionRepository(db);
  final shooterRepo = ShooterRepository(db);
  final drillTemplates = DrillTemplateRepository(db);
  final rangeView = RangeSessionView(
    sessions: sessionRepo,
    preferences: preferences,
  );
  final audio = AudioService();
  await audio.init();
  final tts = await FlutterTtsPort.create();
  final themeController = ThemeController();

  await OrphanRecovery.sweep(sessionRepo);

  final shooterState = ShooterState(shooterRepo);
  await shooterState.initialize();

  final appState = AppState(
    sessions: sessionRepo,
    shooterState: shooterState,
    preferences: preferences,
    audio: audio,
    tts: tts,
    rangeSessionView: rangeView,
    drillTemplates: drillTemplates,
  );
  await appState.hydratePreferences();

  runApp(
    MultiProvider(
      providers: [
        Provider<ShooterRepository>.value(value: shooterRepo),
        Provider<SessionRepository>.value(value: sessionRepo),
        Provider<DrillTemplateRepository>.value(value: drillTemplates),
        Provider<RangeSessionView>.value(value: rangeView),
        Provider<PreferencesRepository>.value(value: preferences),
        ChangeNotifierProvider<ShooterState>.value(value: shooterState),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
        ChangeNotifierProvider<AppState>.value(value: appState),
      ],
      child: const AtriarchApp(),
    ),
  );
}

class AtriarchApp extends StatelessWidget {
  const AtriarchApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return MaterialApp(
      title: 'Atriarch',
      theme: buildAtriarchDarkTheme(),
      darkTheme: buildAtriarchDarkTheme(),
      themeMode: theme.themeMode,
      // Web runs have no native BLE (flutter_blue_plus doesn't support web).
      // Skip the Bluetooth adapter gate so Chrome previews land on Home.
      home: kIsWeb
          ? const HomeScreen()
          : StreamBuilder<BluetoothAdapterState>(
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

class _WebPreviewApp extends StatelessWidget {
  const _WebPreviewApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: buildAtriarchDarkTheme(),
        darkTheme: buildAtriarchDarkTheme(),
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: Center(
            child: Text('Atriarch web preview — tactical theme only'),
          ),
        ),
      );
}
