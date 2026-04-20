import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_primary_button.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';
import '../widgets/tactical/tactical_status_chip.dart';
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
        SnackBar(content: Text('Connection failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalScaffold(
      title: 'TRANSMITTER // PAIRING',
      trailing: StreamBuilder<bool>(
        stream: FlutterBluePlus.isScanning,
        initialData: false,
        builder: (context, snapshot) {
          final scanning = snapshot.data ?? false;
          return TacticalStatusChip(
            color: scanning ? tokens.statusArmed : tokens.statusOffline,
            label: scanning ? 'scanning' : 'idle',
          );
        },
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            FlutterBluePlus.startScan(timeout: const Duration(seconds: 4)),
        child: ListView(
          padding: const EdgeInsets.all(AtriarchSpacing.lg),
          children: [
            const TacticalSection(
              code: 'PARAM_01',
              trailing: 'SCAN_CONTROL',
            ),
            const SizedBox(height: AtriarchSpacing.sm),
            StreamBuilder<bool>(
              stream: FlutterBluePlus.isScanning,
              initialData: false,
              builder: (context, snapshot) {
                final scanning = snapshot.data ?? false;
                return TacticalPrimaryButton(
                  label: scanning ? 'scanning' : 'scan for transmitters',
                  icon: scanning ? null : Icons.bluetooth_searching,
                  variant: scanning
                      ? TacticalButtonVariant.loading
                      : TacticalButtonVariant.primary,
                  onPressed: () {
                    if (scanning) {
                      FlutterBluePlus.stopScan();
                    } else {
                      FlutterBluePlus.startScan(
                        timeout: const Duration(seconds: 4),
                      );
                    }
                  },
                );
              },
            ),
            const SizedBox(height: AtriarchSpacing.xl),
            const TacticalSection(
              code: 'PARAM_02',
              trailing: 'DEVICES_DETECTED',
            ),
            const SizedBox(height: AtriarchSpacing.sm),
            StreamBuilder<List<ScanResult>>(
              stream: FlutterBluePlus.scanResults,
              initialData: const [],
              builder: (context, snapshot) {
                final results = snapshot.data ?? [];
                if (results.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(AtriarchSpacing.lg),
                    child: Text(
                      'SCANNING FOR DEVICES…',
                      style: AtriarchText.labelTiny(
                        color: tokens.textTertiary,
                      ),
                    ),
                  );
                }
                return Column(
                  children: results.map((r) {
                    final name = r.device.platformName.isNotEmpty
                        ? r.device.platformName
                        : r.device.remoteId.toString();
                    return Padding(
                      padding: const EdgeInsets.only(
                        bottom: AtriarchSpacing.sm,
                      ),
                      child: TacticalCard(
                        accent: r.advertisementData.connectable
                            ? tokens.statusHit
                            : tokens.border,
                        onTap: r.advertisementData.connectable
                            ? () => _connectAndNavigate(r.device)
                            : null,
                        child: Row(
                          children: [
                            Icon(
                              Icons.bluetooth,
                              color: tokens.statusHit,
                              size: 18,
                            ),
                            const SizedBox(width: AtriarchSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    r.device.remoteId.toString(),
                                    style: AtriarchText.labelTiny(
                                      color: tokens.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${r.rssi} dBm',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
