import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/atriarch_theme.dart';
import '../home_screen.dart';
import 'discover_targets_step.dart';
import 'first_drill_step.dart';
import 'pair_transmitter_step.dart';
import 'welcome_step.dart';

/// Total step count for the onboarding wizard (addendum §7.10).
const int _kOnboardingStepCount = 4;

/// First-run onboarding wizard (Gate 2 #19).
///
/// Linear 4-step flow (Welcome / Pair Transmitter / Discover Targets / First
/// Drill). Parent Scaffold owns the step index; each step is pushed via a
/// [PageView] with physics disabled so the user must use the step buttons.
/// Close icon in the AppBar triggers a "Quit setup?" confirmation that pops
/// back to Home without flipping the onboarding-complete flag, so a fresh
/// launch replays the wizard.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= _kOnboardingStepCount) return;
    setState(() => _index = index);
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _confirmQuit() async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Quit setup?'),
          content: const Text(
            'You can re-run onboarding from Settings later. '
            'Your transmitter pairing will still be saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Keep going'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Quit'),
            ),
          ],
        );
      },
    );
    if (quit != true) return;
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  /// Called from step 4's skip-when-too-few-targets branch. Marks onboarding
  /// complete even without a practice drill — acceptable per spec because
  /// the user can't run one without hardware and we don't want them stuck.
  Future<void> _finishWithoutDrill() async {
    await context.read<AppState>().setOnboardingComplete(true);
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = _index + 1;
    return Scaffold(
      appBar: AppBar(
        title: Text('Setup · Step $step of $_kOnboardingStepCount'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Quit setup',
          onPressed: _confirmQuit,
        ),
      ),
      body: SafeArea(
        child: PageView(
          controller: _controller,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (i) => setState(() => _index = i),
          children: [
            WelcomeStep(onContinue: () => _goTo(1)),
            PairTransmitterStep(onPaired: () => _goTo(2)),
            DiscoverTargetsStep(
              onContinue: () => _goTo(3),
              onSkip: () => _goTo(3),
            ),
            FirstDrillStep(onSkipNoTargets: _finishWithoutDrill),
          ],
        ),
      ),
    );
  }
}

/// `●●○○` dot row used at the top of every onboarding step. [currentStep]
/// is 1-indexed so callers can write `currentStep: 2` for the second step
/// without doing mental arithmetic.
class OnboardingStepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const OnboardingStepIndicator({
    super.key,
    required this.currentStep,
    this.totalSteps = _kOnboardingStepCount,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Semantics(
      label: 'Step $currentStep of $totalSteps',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(totalSteps, (i) {
          final filled = i < currentStep;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AtriarchSpacing.xs),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? tokens.statusLive : tokens.textTertiary,
              ),
            ),
          );
        }),
      ),
    );
  }
}
