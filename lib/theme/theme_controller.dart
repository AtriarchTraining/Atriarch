import 'package:flutter/material.dart';

/// Dark-only theme controller (Stage 3 gate decision).
///
/// Gate-2's `ThemePreference.light`/`auto` and the `screen_brightness`
/// outdoor-rule were stripped — see
/// `docs/superpowers/plans/2026-04-21-stage-3-gate2-integration.md`.
///
/// Left as a ChangeNotifier so future dark-only-with-drill-brightness-
/// override work can reintroduce lifecycle hooks here without the
/// MaterialApp wiring changing. For now it's a constant: always
/// [ThemeMode.dark].
class ThemeController extends ChangeNotifier {
  ThemeMode get themeMode => ThemeMode.dark;
}
