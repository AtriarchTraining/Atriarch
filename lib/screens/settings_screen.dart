import 'package:flutter/material.dart';

/// Settings screen — Phase-3 TODO stub.
///
/// Gate-2 shipped a Theme/Ready-Audio/Onboarding settings screen that
/// referenced `ThemePreference` (collapsed to dark-only in Stage-3),
/// `readyAudioEnabled`/`readyAudioVolume` on AppState (not yet ported), and
/// `setOnboardingComplete(false)` (the AppState API is
/// `markOnboardingComplete()`).
///
/// Phase-3 Task 3.x rewrites this screen tactically. For Phase-2 exit the
/// tree must compile cleanly — this stub keeps the public type `SettingsScreen`
/// importable so `home_screen.dart` can route to it, and shows a placeholder
/// until the real Phase-3 content lands.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Settings — Phase 3 TODO.\n\n'
            'Theme is dark-only (Stage-3 gate). Ready-audio toggle + volume '
            'and onboarding re-entry will land in Phase 3 tactical retrofit.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
