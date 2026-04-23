import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/drill_config.dart';
import '../../models/target_unit.dart';
import '../../state/app_state.dart';
import '../../theme/atriarch_theme.dart';
import '../drill_running_screen.dart';
import 'onboarding_flow.dart';

/// Step 4 of the first-run wizard (Gate 2 #19, addendum §7.10).
///
/// Pre-fills a conservative Program B drill against the first two online
/// targets. When fewer than 2 online targets are available the step
/// auto-advances to the flow's completion handler (the wizard finishes
/// without running a practice drill).
class FirstDrillStep extends StatefulWidget {
  final VoidCallback onSkipNoTargets;

  const FirstDrillStep({super.key, required this.onSkipNoTargets});

  @override
  State<FirstDrillStep> createState() => _FirstDrillStepState();
}

class _FirstDrillStepState extends State<FirstDrillStep> {
  bool _starting = false;

  List<TargetUnit> _onlineTargets(AppState state) {
    return state.targets.where((t) => t.isOnline).toList();
  }

  DrillConfig _buildConfig(List<TargetUnit> online) {
    final picks = online.take(2).map((t) => t.id).toList(growable: false);
    return DrillConfig(
      programType: ProgramType.programB,
      startMin: 1.5,
      startMax: 3.0,
      delayMin: 1.0,
      delayMax: 2.0,
      hitsMin: 1,
      hitsMax: 1,
      iterations: 3,
      targetIds: picks,
      noShootIds: const <int>[],
    );
  }

  Future<void> _start() async {
    if (_starting) return;
    final state = context.read<AppState>();
    final online = _onlineTargets(state);
    if (online.length < 2) {
      widget.onSkipNoTargets();
      return;
    }
    setState(() => _starting = true);
    final config = _buildConfig(online);
    // Phase-3 TODO: re-introduce presetName + onboardingMode once
    // DrillTemplate wiring + DrillRunningScreen onboarding flag are ported.
    await state.startDrill(config);
    if (!mounted) return;
    // pushReplacement so Back from Results inside onboarding lands on the
    // wizard step (which pops to Home), not back on the Drill screen.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const DrillRunningScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Consumer<AppState>(
      builder: (_, state, __) {
        final online = _onlineTargets(state);
        final hasEnough = online.length >= 2;
        return Padding(
          padding: const EdgeInsets.all(AtriarchSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const OnboardingStepIndicator(currentStep: 4),
              const SizedBox(height: AtriarchSpacing.xl),
              Text(
                'Run your first drill',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AtriarchSpacing.sm),
              Text(
                hasEnough
                    ? 'We set up a gentle Program B practice with the '
                        'first two online targets (three iterations, '
                        'one hit each).'
                    : 'We need at least two online targets for a practice '
                        'drill. Tap Finish to wrap up — no hardware work '
                        'is needed.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
              ),
              const SizedBox(height: AtriarchSpacing.xl),
              Container(
                padding: const EdgeInsets.all(AtriarchSpacing.lg),
                decoration: BoxDecoration(
                  color: tokens.bgCard,
                  border: Border.all(color: tokens.border),
                  borderRadius: BorderRadius.circular(AtriarchRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FactRow(
                      label: 'Program',
                      value: 'Program B — Individual',
                      tokens: tokens,
                    ),
                    _FactRow(
                      label: 'Iterations',
                      value: '3',
                      tokens: tokens,
                    ),
                    _FactRow(
                      label: 'Start delay',
                      value: '1.5–3.0 s',
                      tokens: tokens,
                    ),
                    _FactRow(
                      label: 'Between activations',
                      value: '1.0–2.0 s',
                      tokens: tokens,
                    ),
                    _FactRow(
                      label: 'Required hits',
                      value: '1',
                      tokens: tokens,
                    ),
                    _FactRow(
                      label: 'Targets',
                      value: hasEnough
                          ? online
                              .take(2)
                              .map((t) =>
                                  state.targetNames[t.id] ?? 'Target ${t.id}')
                              .join(', ')
                          : 'Not enough online',
                      tokens: tokens,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (!hasEnough)
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: AtriarchSpacing.md,
                  ),
                  child: Text(
                    'Not enough targets for a practice drill — '
                    'finishing onboarding.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textTertiary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _starting
                      ? null
                      : (hasEnough ? _start : widget.onSkipNoTargets),
                  child: Text(hasEnough ? 'Start' : 'Finish'),
                ),
              ),
              const SizedBox(height: AtriarchSpacing.md),
            ],
          ),
        );
      },
    );
  }
}

class _FactRow extends StatelessWidget {
  final String label;
  final String value;
  final AtriarchTokens tokens;

  const _FactRow({
    required this.label,
    required this.value,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AtriarchSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
