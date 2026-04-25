import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_primary_button.dart';
import '../widgets/tactical/tactical_scaffold.dart';

class TargetSetupScreen extends StatefulWidget {
  const TargetSetupScreen({super.key});

  @override
  State<TargetSetupScreen> createState() => _TargetSetupScreenState();
}

class _TargetSetupScreenState extends State<TargetSetupScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // ignore: discarded_futures
      _runDiscovery();
    });
  }

  Future<void> _runDiscovery() async {
    try {
      await context.read<AppState>().discoverTargets();
    } catch (_) {
      // Silent — online count staying at zero is the signal.
    }
  }

  Future<void> _onWalkTheRange() async {
    // TODO(walk-range): full Walk-the-Range drop-in deferred to Gate 2 #20.
    await _runDiscovery();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Walk the range to wake every target. '
            'Full guided flow lands in the next update.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalScaffold(
      title: 'TARGET SETUP',
      body: Padding(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your transmitter is polling the target fleet. '
              'Use Walk-the-Range to identify each target in turn.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
            ),
            const SizedBox(height: AtriarchSpacing.xl),
            Consumer<AppState>(
              builder: (_, state, __) {
                final total = state.targets.length;
                final online = state.targets.where((t) => t.isOnline).length;
                final denominator = total == 0 ? '?' : total.toString();
                return Container(
                  padding: const EdgeInsets.all(AtriarchSpacing.lg),
                  decoration: BoxDecoration(
                    color: tokens.bgCard,
                    borderRadius: BorderRadius.circular(AtriarchRadius.md),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Row(
                    children: [
                      if (state.isScanning)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      else
                        Icon(
                          online > 0 ? Icons.check_circle : Icons.radar,
                          color: online > 0
                              ? tokens.statusLive
                              : tokens.textTertiary,
                        ),
                      const SizedBox(width: AtriarchSpacing.md),
                      Expanded(
                        child: Text(
                          '$online of $denominator targets online',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AtriarchSpacing.xl),
            TacticalPrimaryButton(
              label: 'WALK_THE_RANGE',
              icon: Icons.directions_walk,
              onPressed: _onWalkTheRange,
            ),
            const SizedBox(height: AtriarchSpacing.md),
            const TacticalPrimaryButton(
              label: 'PHOTO_MAP',
              icon: Icons.photo_camera_outlined,
              variant: TacticalButtonVariant.disabled,
            ),
            const SizedBox(height: AtriarchSpacing.md),
            TacticalPrimaryButton(
              label: 'RESCAN',
              onPressed: _runDiscovery,
            ),
          ],
        ),
      ),
    );
  }
}
