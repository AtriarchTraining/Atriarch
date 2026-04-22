import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../theme/theme_controller.dart';
import 'onboarding/onboarding_flow.dart';

/// First settings-bearing screen. Designed for later Wave 2 items to stack
/// additional `_SettingsSection` children into the same ListView.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          _ThemeSection(),
          _ReadyAudioSection(),
          _OnboardingSection(),
        ],
      ),
    );
  }
}

class _ThemeSection extends StatelessWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeController>(
      builder: (context, ctrl, _) {
        return _SettingsSection(
          title: 'Theme',
          child: RadioGroup<ThemePreference>(
            groupValue: ctrl.preference,
            onChanged: (v) {
              if (v != null) ctrl.setPreference(v);
            },
            child: const Column(
              children: [
                RadioListTile<ThemePreference>(
                  value: ThemePreference.auto,
                  title: Text('Auto (time of day)'),
                  subtitle: Text(
                    'Light from 06:00 to 18:00, dark otherwise.',
                  ),
                ),
                RadioListTile<ThemePreference>(
                  value: ThemePreference.light,
                  title: Text('Light'),
                ),
                RadioListTile<ThemePreference>(
                  value: ThemePreference.dark,
                  title: Text('Dark'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Gate 2 #15 (§4.C). Toggle + volume for the ready-chime that plays when
/// all targets come online at the end of a discovery cycle.
class _ReadyAudioSection extends StatelessWidget {
  const _ReadyAudioSection();

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Consumer<AppState>(
      builder: (context, state, _) {
        final enabled = state.readyAudioEnabled;
        return _SettingsSection(
          title: 'Ready Audio',
          child: Column(
            children: [
              SwitchListTile(
                value: enabled,
                onChanged: (v) => state.setReadyAudioEnabled(v),
                secondary: const Icon(Icons.volume_up),
                title: const Text('Enable ready chime'),
                subtitle: const Text(
                  'Plays a short bell when all targets are online. '
                  'Respects iPhone silent mode.',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AtriarchSpacing.lg,
                  AtriarchSpacing.xs,
                  AtriarchSpacing.lg,
                  AtriarchSpacing.md,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        'Volume',
                        style: TextStyle(
                          color: enabled
                              ? tokens.textPrimary
                              : tokens.textTertiary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: state.readyAudioVolume.clamp(0.0, 1.0),
                        onChanged: enabled
                            ? (v) => state.setReadyAudioVolume(v)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Gate 2 #19. Re-entry point for the first-run wizard. Tapping resets the
/// `onboarding_complete` flag and pushes the wizard in place of the current
/// route so the back stack doesn't leak into post-onboarding UI.
class _OnboardingSection extends StatelessWidget {
  const _OnboardingSection();

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return _SettingsSection(
      title: 'Onboarding',
      child: ListTile(
        leading: Icon(Icons.replay, color: tokens.textSecondary),
        title: const Text('Re-run onboarding'),
        subtitle: Text(
          'Replay the first-run wizard. Your transmitter pairing will be kept.',
          style: TextStyle(color: tokens.textTertiary),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final state = context.read<AppState>();
          final navigator = Navigator.of(context);
          await state.setOnboardingComplete(false);
          navigator.pushReplacement(
            MaterialPageRoute(builder: (_) => const OnboardingFlow()),
          );
        },
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AtriarchSpacing.lg,
            AtriarchSpacing.xl,
            AtriarchSpacing.lg,
            AtriarchSpacing.sm,
          ),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: tokens.textTertiary,
            ),
          ),
        ),
        Divider(height: 1, color: tokens.border),
        child,
        Divider(height: 1, color: tokens.border),
      ],
    );
  }
}
