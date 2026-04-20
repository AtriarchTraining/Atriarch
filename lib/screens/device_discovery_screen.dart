import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'home_screen.dart';

class DeviceDiscoveryScreen extends StatefulWidget {
  const DeviceDiscoveryScreen({super.key});

  @override
  State<DeviceDiscoveryScreen> createState() => _DeviceDiscoveryScreenState();
}

class _DeviceDiscoveryScreenState extends State<DeviceDiscoveryScreen> {
  @override
  void initState() {
    super.initState();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
  }

  Future<void> _connectAndNavigate(BluetoothDevice device) async {
    final appState = context.read<AppState>();
    try {
      await appState.bleService.connect(device);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find Transmitter')),
      body: RefreshIndicator(
        onRefresh: () =>
            FlutterBluePlus.startScan(timeout: const Duration(seconds: 4)),
        child: StreamBuilder<List<ScanResult>>(
          stream: FlutterBluePlus.scanResults,
          initialData: const [],
          builder: (context, snapshot) {
            final results = snapshot.data ?? [];
            if (results.isEmpty) {
              return const Center(child: Text('Scanning for devices...'));
            }
            return ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final r = results[index];
                final name = r.device.platformName.isNotEmpty
                    ? r.device.platformName
                    : r.device.remoteId.toString();
                return ListTile(
                  title: Text(name),
                  subtitle: Text(r.device.remoteId.toString()),
                  trailing: Text('${r.rssi} dBm'),
                  onTap: r.advertisementData.connectable
                      ? () => _connectAndNavigate(r.device)
                      : null,
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: StreamBuilder<bool>(
        stream: FlutterBluePlus.isScanning,
        initialData: false,
        builder: (context, snapshot) {
          final scanning = snapshot.data ?? false;
          return FloatingActionButton(
            onPressed: scanning
                ? FlutterBluePlus.stopScan
                : () => FlutterBluePlus.startScan(
                    timeout: const Duration(seconds: 4)),
            child: Icon(scanning ? Icons.stop : Icons.search),
          );
        },
      ),
    );
  }
}
