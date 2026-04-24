import 'package:flutter/material.dart';

import '../../theme/atriarch_theme.dart';
import '../../widgets/tactical/tactical_primary_button.dart';
import 'onboarding_flow.dart';

/// Step 1 of the first-run wizard (Gate 2 #19, addendum §7.10).
///
/// Single-sentence product statement + a primary `Continue` button that
/// advances to [PairTransmitterStep]. No BLE or persistence side effects.
class WelcomeStep extends StatelessWidget {
  final VoidCallback onContinue;

  const WelcomeStep({super.key, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Padding(
      padding: const EdgeInsets.all(AtriarchSpacing.lg),
      child: Column(
        children: [
          const OnboardingStepIndicator(currentStep: 1),
          const SizedBox(height: AtriarchSpacing.hero),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.gps_fixed,
                    size: 72,
                    color: tokens.statusLive,
                  ),
                  const SizedBox(height: AtriarchSpacing.xl),
                  Text(
                    'WELCOME TO ATRIARCH',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.4,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AtriarchSpacing.xl),
                  Text(
                    'Atriarch turns a wireless target fleet into a '
                    'live-fire drill console.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: tokens.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          TacticalPrimaryButton(
            label: 'CONTINUE',
            onPressed: onContinue,
          ),
          const SizedBox(height: AtriarchSpacing.xl),
        ],
      ),
    );
  }
}
