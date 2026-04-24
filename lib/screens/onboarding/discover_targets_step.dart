import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/atriarch_theme.dart';
import '../../widgets/tactical/tactical_primary_button.dart';
import 'onboarding_flow.dart';

/// Step 3 of the first-run wizard (Gate 2 #19, addendum §7.10).
///
/// Runs target discovery, shows live online-count, and offers two setup
/// paths (Walk-the-Range / Photo Map) plus Skip. Photo Map is disabled
/// per spec (Gate 3 scope); Walk-the-Range is a placeholder — full impl
/// lands with Gate 2 #20.
class DiscoverTargetsStep extends StatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  const DiscoverTargetsStep({
    super.key,
    required this.onContinue,
    required this.onSkip,
  });

  @override
  State<DiscoverTargetsStep> createState() => _DiscoverTargetsStepState();
}

class _DiscoverTargetsStepState extends State<DiscoverTargetsStep> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Best-effort: BLE may not be connected in demos. discoverTargets()
      // rethrows write errors; swallow here so the UI still lets the user
      // proceed via Skip.
      // ignore: discarded_futures
      _runDiscovery();
    });
  }

  Future<void> _runDiscovery() async {
    try {
      await context.read<AppState>().discoverTargets();
    } catch (_) {
      // Silent — the online count staying at zero is the signal.
    }
  }

  Future<void> _onWalkTheRange() async {
    // TODO(walk-range): full Walk-the-Range drop-in lands with Gate 2 #20.
    // For now re-trigger a discovery so the user sees the count update.
    await _runDiscovery();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Walk the range to wake every target. '
            'Full guided flow lands in the next update.'),
      ),
    );
  }

  Future<void> _onSkip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Skip target identification?'),
          content: const Text(
            "Skipping means you'll need to identify targets manually "
            'during drills. Continue anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Skip anyway'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) widget.onSkip();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Padding(
      padding: const EdgeInsets.all(AtriarchSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OnboardingStepIndicator(currentStep: 3),
          const SizedBox(height: AtriarchSpacing.xl),
          Text(
            'DISCOVER TARGETS',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  letterSpacing: 2.4,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AtriarchSpacing.sm),
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
          // Walk-the-Range placeholder. Full drop-in = Gate 2 #20.
          TacticalPrimaryButton(
            label: 'WALK_THE_RANGE',
            icon: Icons.directions_walk,
            onPressed: _onWalkTheRange,
          ),
          const SizedBox(height: AtriarchSpacing.md),
          // Photo Map — disabled per spec (Gate 3 scope).
          const TacticalPrimaryButton(
            label: 'PHOTO_MAP',
            icon: Icons.photo_camera_outlined,
            variant: TacticalButtonVariant.disabled,
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _onSkip,
                  child: Text(
                    'SKIP',
                    style: AtriarchText.labelTiny(color: tokens.textTertiary),
                  ),
                ),
              ),
              const SizedBox(width: AtriarchSpacing.md),
              Expanded(
                child: Consumer<AppState>(
                  builder: (_, state, __) {
                    final anyOnline =
                        state.targets.any((t) => t.isOnline);
                    return TacticalPrimaryButton(
                      label: 'CONTINUE',
                      variant: anyOnline
                          ? TacticalButtonVariant.primary
                          : TacticalButtonVariant.disabled,
                      onPressed: anyOnline ? widget.onContinue : null,
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AtriarchSpacing.md),
        ],
      ),
    );
  }
}
