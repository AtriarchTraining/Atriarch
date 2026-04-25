import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_primary_button.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';
import 'onboarding/onboarding_flow.dart';

/// Settings — tactical retrofit (Stage-3 Phase-3 Task 3.6).
///
/// Theme toggle dropped (dark-only gate, memory: project_theme_dark_only.md).
/// Ready-audio toggle deferred to Phase 4 (AppState wiring not yet ported).
/// Ships three sections: target visibility, range-session control, and
/// onboarding replay.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalScaffold(
      title: 'SETTINGS',
      body: ListView(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        children: [
          const TacticalSection(code: 'SET_00', trailing: 'TARGETS'),
          const SizedBox(height: AtriarchSpacing.sm),
          Consumer<AppState>(
            builder: (_, state, __) => TacticalCard(
              child: SwitchListTile(
                title: Text(
                  'SHOW_REMOVED',
                  style: AtriarchText.labelTiny(color: tokens.statusHit),
                ),
                subtitle: Text(
                  'Include soft-deleted targets in setup screens.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textTertiary,
                      ),
                ),
                value: state.showRemoved,
                activeThumbColor: tokens.statusLive,
                onChanged: (_) => state.toggleShowRemoved(),
              ),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(
            code: 'SET_01',
            trailing: 'RANGE_SESSION',
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalCard(
            child: Padding(
              padding: const EdgeInsets.all(AtriarchSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.only(bottom: AtriarchSpacing.sm),
                    child: Text(
                      'Start a fresh range session. Historical drills stay '
                      'in the database; only the current-session cutoff moves '
                      'forward.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: tokens.textTertiary,
                          ),
                    ),
                  ),
                  Consumer<AppState>(
                    builder: (_, state, __) => TacticalPrimaryButton(
                      label: 'CLEAR_CURRENT_SESSION',
                      onPressed: state.rangeSessionView == null
                          ? null
                          : () async {
                              await state.rangeSessionView!.clearCurrent();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Range session cleared. '
                                    'Recent drills reset to empty.',
                                  ),
                                ),
                              );
                            },
                      variant: state.rangeSessionView == null
                          ? TacticalButtonVariant.disabled
                          : TacticalButtonVariant.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(
            code: 'SET_02',
            trailing: 'READY_AUDIO',
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          Consumer<AppState>(
            builder: (_, state, __) => TacticalCard(
              child: Padding(
                padding: const EdgeInsets.all(AtriarchSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      title: Text(
                        'PLAY_READY_CHIME',
                        style: AtriarchText.labelTiny(color: tokens.statusHit),
                      ),
                      subtitle: Text(
                        'Plays once when all targets come online after a '
                        'discovery cycle.',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: tokens.textTertiary,
                                ),
                      ),
                      value: state.readyAudioEnabled,
                      activeThumbColor: tokens.statusLive,
                      onChanged: (v) => state.setReadyAudioEnabled(v),
                    ),
                    if (state.readyAudioEnabled)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AtriarchSpacing.md,
                          vertical: AtriarchSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Text(
                              'VOLUME',
                              style:
                                  AtriarchText.labelTiny(color: tokens.statusHit),
                            ),
                            const SizedBox(width: AtriarchSpacing.md),
                            Expanded(
                              child: Slider(
                                value: state.readyAudioVolume,
                                activeColor: tokens.statusLive,
                                onChanged: (v) => state.setReadyAudioVolume(v),
                              ),
                            ),
                            SizedBox(
                              width: 44,
                              child: Text(
                                '${(state.readyAudioVolume * 100).round()}%',
                                textAlign: TextAlign.right,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: tokens.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(
            code: 'SET_03',
            trailing: 'ONBOARDING',
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalCard(
            child: Padding(
              padding: const EdgeInsets.all(AtriarchSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.only(bottom: AtriarchSpacing.sm),
                    child: Text(
                      'Replay the first-run wizard. Your transmitter pairing '
                      'stays saved.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: tokens.textTertiary,
                          ),
                    ),
                  ),
                  TacticalPrimaryButton(
                    label: 'REPLAY_ONBOARDING',
                    onPressed: () async {
                      final state = context.read<AppState>();
                      final navigator = Navigator.of(context);
                      await state.resetOnboarding();
                      if (!context.mounted) return;
                      navigator.pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const OnboardingFlow(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.xxl),
        ],
      ),
    );
  }
}
