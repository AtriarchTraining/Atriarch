import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../util/target_name_resolver.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_primary_button.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';
import '../widgets/tactical/tactical_status_chip.dart';
import 'device_discovery_screen.dart';
import 'onboarding/onboarding_flow.dart';
import 'program_a_setup_screen.dart';
import 'program_b_setup_screen.dart';
import 'recent_drills_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Gate the home layout on onboarding completion: first launch should
    // land on the wizard, not the dashboard.
    final state = context.watch<AppState>();
    if (!state.onboardingComplete) {
      return const OnboardingFlow();
    }
    return TacticalScaffold(
      title: 'ATRIARCH // HOME',
      body: ListView(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        children: [
          const _ConnectionBanner(),
          const SizedBox(height: AtriarchSpacing.lg),
          const TacticalSection(code: 'PARAM_01', trailing: 'PROTOCOL_SELECT'),
          const SizedBox(height: AtriarchSpacing.sm),
          _HomeCard(
            code: 'TARGET_SETUP',
            title: 'TARGET SETUP',
            subtitle: 'Scan the fleet, identify units, mark no-shoots.',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Target Discovery screen not built yet.'),
                ),
              );
            },
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          _HomeCard(
            code: 'PROGRAM_A',
            title: 'GROUP MODE',
            subtitle: 'Up to 5 groups. One active target per group.',
            accent: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProgramASetupScreen(),
              ),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          _HomeCard(
            code: 'PROGRAM_B',
            title: 'INDIVIDUAL MODE',
            subtitle: 'Every target runs its own reaction drill.',
            accent: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProgramBSetupScreen(),
              ),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(code: 'NAV_00', trailing: 'UTILITIES'),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalPrimaryButton(
            label: 'RECENT_DRILLS',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecentDrillsScreen()),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalPrimaryButton(
            label: 'SETTINGS',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalPrimaryButton(
            label: 'WALK_THE_RANGE',
            onPressed: () => _startWalkTheRange(context),
          ),
        ],
      ),
    );
  }

  Future<void> _startWalkTheRange(BuildContext context) async {
    final state = context.read<AppState>();
    final resolver = TargetNameResolver(state.targetNames);
    for (final target in state.targets.where((t) => t.isOnline)) {
      final name = resolver.display(target.id);
      await state.tts?.speak(name);
      await state.identifyTarget(target.id);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
}

class _HomeCard extends StatelessWidget {
  final String code;
  final String title;
  final String subtitle;
  final bool accent;
  final VoidCallback onTap;

  const _HomeCard({
    required this.code,
    required this.title,
    required this.subtitle,
    this.accent = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalCard(
      accent: accent ? tokens.statusHit : tokens.border,
      padding: const EdgeInsets.all(AtriarchSpacing.lg),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  style: AtriarchText.labelTiny(color: tokens.statusHit),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: tokens.textTertiary),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: tokens.textTertiary),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner();

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final bleService = context.read<AppState>().bleService;
    return StreamBuilder<BluetoothConnectionState>(
      stream: bleService.connectionState,
      initialData: bleService.isConnected
          ? BluetoothConnectionState.connected
          : BluetoothConnectionState.disconnected,
      builder: (context, snapshot) {
        final connected = snapshot.data == BluetoothConnectionState.connected;
        final deviceName = bleService.device?.platformName;
        final accent = connected ? tokens.statusLive : tokens.statusViolation;
        return TacticalCard(
          accent: accent,
          background: accent.withValues(alpha: 0.08),
          onTap: connected
              ? null
              : () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DeviceDiscoveryScreen(),
                    ),
                  ),
          child: Row(
            children: [
              TacticalStatusChip(
                color: accent,
                label: connected ? 'connected' : 'disconnected',
              ),
              const SizedBox(width: AtriarchSpacing.sm),
              Expanded(
                child: Text(
                  connected
                      ? (deviceName != null && deviceName.isNotEmpty
                          ? deviceName
                          : 'TRANSMITTER LINKED')
                      : 'TAP TO RECONNECT',
                  style: AtriarchText.labelTiny(color: tokens.textPrimary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
