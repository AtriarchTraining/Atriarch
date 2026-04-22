import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'device_discovery_screen.dart';
import 'program_a_setup_screen.dart';
import 'program_b_setup_screen.dart';
import 'recent_drills_screen.dart';
import 'settings_screen.dart';

// Implements addendum §1 Home screen spec: persistent connection banner +
// 3 tappable rows (Target Setup, Program A, Program B). Style tokens land
// with lib/theme/atriarch_theme.dart (addendum §DESIGN.md).

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atriarch'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const _ConnectionBanner(),
          Expanded(
            child: ListView(
              children: [
                _HomeRow(
                  icon: Icons.gps_fixed,
                  title: 'Target Setup',
                  subtitle: 'Scan the fleet, identify units, mark no-shoots.',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Target Discovery screen (Task 4.1) not built yet.',
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                _HomeRow(
                  icon: Icons.groups,
                  title: 'Program A — Grouped',
                  subtitle:
                      'One active target per group at a time. Up to 5 groups.',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProgramASetupScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                _HomeRow(
                  icon: Icons.person,
                  title: 'Program B — Individual',
                  subtitle:
                      'Each target runs its own reaction drill independently.',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProgramBSetupScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Consumer<AppState>(
                  builder: (_, state, __) {
                    final count = state.sessions.currentSessionDrills.length;
                    if (count == 0) return const SizedBox.shrink();
                    return Column(
                      children: [
                        _HomeRow(
                          icon: Icons.check_circle,
                          title: 'Recent Drills',
                          subtitle: '$count drill${count == 1 ? '' : 's'} '
                              'this session',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RecentDrillsScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner();

  @override
  Widget build(BuildContext context) {
    final bleService = context.read<AppState>().bleService;
    return StreamBuilder<BluetoothConnectionState>(
      stream: bleService.connectionState,
      initialData: bleService.isConnected
          ? BluetoothConnectionState.connected
          : BluetoothConnectionState.disconnected,
      builder: (context, snapshot) {
        final connected = snapshot.data == BluetoothConnectionState.connected;
        final deviceName = bleService.device?.platformName;
        final label = connected
            ? 'Connected${deviceName != null && deviceName.isNotEmpty ? " · $deviceName" : ""}'
            : 'Disconnected — tap to reconnect';
        return Material(
          color: connected ? Colors.green.shade700 : Colors.red.shade700,
          child: InkWell(
            onTap: connected
                ? null
                : () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DeviceDiscoveryScreen(),
                      ),
                    ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(
                    connected ? Icons.bluetooth : Icons.bluetooth_disabled,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
