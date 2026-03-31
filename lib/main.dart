import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'state/app_state.dart';
import 'screens/device_discovery_screen.dart';

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
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
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
  }
}

class BluetoothOffScreen extends StatelessWidget {
  const BluetoothOffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_disabled, size: 100, color: Colors.grey),
            SizedBox(height: 16),
            Text('Please enable Bluetooth', style: TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
