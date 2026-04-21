import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'state/app_state.dart';
import 'theme/atriarch_theme.dart';
import 'screens/device_discovery_screen.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const AtriarchApp(),
    ),
  );
}

class AtriarchApp extends StatelessWidget {
  const AtriarchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Atriarch',
      theme: buildAtriarchLightTheme(),
      // Web runs have no native BLE (flutter_blue_plus doesn't support web).
      // Skip the Bluetooth adapter gate entirely so Chrome previews land on
      // Home — useful for UI reviews without hardware.
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
