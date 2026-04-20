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
