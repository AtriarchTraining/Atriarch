import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/atriarch_theme.dart';
import '../theme/theme_controller.dart';

/// First settings-bearing screen. Designed for later Wave 2 items to stack
/// additional `_SettingsSection` children into the same ListView.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Consumer<ThemeController>(
        builder: (context, ctrl, _) {
          return ListView(
            children: [
              _SettingsSection(
                title: 'Theme',
                child: RadioGroup<ThemePreference>(
                  groupValue: ctrl.preference,
                  onChanged: (v) {
                    if (v != null) ctrl.setPreference(v);
                  },
                  child: Column(
                    children: [
                      const RadioListTile<ThemePreference>(
                        value: ThemePreference.auto,
                        title: Text('Auto (ambient light)'),
                        subtitle: Text(
                          'Switch to light outdoors, dark indoors.',
                        ),
                      ),
                      const RadioListTile<ThemePreference>(
                        value: ThemePreference.light,
                        title: Text('Light'),
                      ),
                      const RadioListTile<ThemePreference>(
                        value: ThemePreference.dark,
                        title: Text('Dark'),
                      ),
                      if (ctrl.sensorUnavailable)
                        const _SensorUnavailableNotice(),
                    ],
                  ),
                ),
              ),
            ],
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

class _SensorUnavailableNotice extends StatelessWidget {
  const _SensorUnavailableNotice();

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Padding(
      padding: const EdgeInsets.all(AtriarchSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning, size: 18, color: tokens.statusLate),
          const SizedBox(width: AtriarchSpacing.sm),
          Expanded(
            child: Text(
              'Ambient light sensor unavailable. Auto mode uses a '
              'time-of-day schedule (light 06:00–18:00).',
              style: TextStyle(
                fontSize: 13,
                color: tokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
