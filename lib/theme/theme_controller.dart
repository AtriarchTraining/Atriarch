import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../data/preferences_repository.dart';

/// User preference for theme selection.
///
/// - [auto] — time-of-day schedule (06:00–18:00 local = LIGHT, else DARK).
///   iPhone has no reliable ambient-light Flutter plugin, so the schedule
///   is the design, not a fallback.
/// - [light] — always light; brightness override applies on drill/setup.
/// - [dark] — always dark; no brightness override.
enum ThemePreference {
  auto,
  light,
  dark;

  String get persistenceKey => name;

  static ThemePreference fromKey(String? key) {
    switch (key) {
      case 'light':
        return ThemePreference.light;
      case 'dark':
        return ThemePreference.dark;
      case 'auto':
      default:
        return ThemePreference.auto;
    }
  }
}

/// Tiny abstraction over [ScreenBrightness] so tests can inject a fake
/// without patching the singleton. Implemented by [_RealBrightnessController]
/// in production.
abstract class BrightnessController {
  Future<double> get current;
  Future<void> setBrightness(double value);
}

class _RealBrightnessController implements BrightnessController {
  @override
  Future<double> get current => ScreenBrightness().current;

  @override
  Future<void> setBrightness(double value) =>
      ScreenBrightness().setScreenBrightness(value);
}

/// Drives `MaterialApp.themeMode` + outdoor-rule brightness override.
///
/// Auto mode uses a local-time schedule: hour ∈ [6, 18) → LIGHT, else DARK.
/// A once-per-minute `Timer.periodic` re-evaluates so the theme flips
/// cleanly when the user's clock crosses 06:00 or 18:00 while the app is
/// open.
///
/// Brightness override (§Outdoor rule): only when [setDrillContextActive]
/// is true AND resolved theme is LIGHT. Captures the prior brightness once
/// per override so `restore` is lossless. On lifecycle `paused`/`inactive`
/// the override is released; on resume + still in LIGHT + still in context,
/// it re-applies.
class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  static const String preferenceSettingKey = 'theme_preference';
  static const Duration _scheduleTickInterval = Duration(minutes: 1);
  static const double _maxBrightness = 1.0;

  final PreferencesRepository _preferences;
  final BrightnessController _brightness;
  final WidgetsBinding _binding;
  final DateTime Function() _now;

  ThemeController({
    required PreferencesRepository preferences,
    BrightnessController? brightnessOverride,
    WidgetsBinding? binding,
    DateTime Function()? now,
  })  : _preferences = preferences,
        _brightness = brightnessOverride ?? _RealBrightnessController(),
        _binding = binding ?? WidgetsBinding.instance,
        _now = now ?? DateTime.now;

  ThemePreference _preference = ThemePreference.auto;
  ThemeMode _themeMode = ThemeMode.light;
  bool _drillContextActive = false;

  // Once-per-minute re-evaluation of the schedule while the user is in auto.
  Timer? _scheduleTicker;

  // Brightness-override bookkeeping.
  double? _capturedBrightness;
  bool _overrideApplied = false;

  bool _disposed = false;

  ThemeMode get themeMode => _themeMode;
  ThemePreference get preference => _preference;
  bool get drillContextActive => _drillContextActive;

  /// Load persisted preference and start lifecycle observation. Safe to call
  /// once per app session.
  Future<void> init() async {
    _binding.addObserver(this);
    final stored =
        await _preferences.getSetting<String>(preferenceSettingKey);
    _preference = ThemePreference.fromKey(stored);
    _applyPreference(notify: false);
    if (_preference == ThemePreference.auto) {
      _startScheduleTicker();
    }
  }

  /// Explicit cleanup; [ChangeNotifier.dispose] is still called.
  @override
  void dispose() {
    _disposed = true;
    _binding.removeObserver(this);
    _scheduleTicker?.cancel();
    _scheduleTicker = null;
    // Best-effort restore on teardown.
    if (_overrideApplied) {
      unawaited(_restoreBrightness());
    }
    super.dispose();
  }

  /// User toggled the Settings radio. Persists immediately.
  Future<void> setPreference(ThemePreference pref) async {
    if (pref == _preference) return;
    _preference = pref;
    await _preferences.setSetting<String>(
      preferenceSettingKey,
      pref.persistenceKey,
    );

    if (pref == ThemePreference.auto) {
      _startScheduleTicker();
    } else {
      _scheduleTicker?.cancel();
      _scheduleTicker = null;
    }
    _applyPreference();
  }

  /// Mark that the user is in a drill/setup screen. Only while true will
  /// LIGHT theme trigger the [_maxBrightness] brightness override.
  void setDrillContextActive(bool active) {
    if (active == _drillContextActive) return;
    _drillContextActive = active;
    if (active) {
      _maybeApplyBrightnessOverride();
    } else {
      unawaited(_restoreBrightness());
    }
  }

  // -------------------------------------------------------------- Schedule

  void _startScheduleTicker() {
    _scheduleTicker?.cancel();
    _scheduleTicker = Timer.periodic(_scheduleTickInterval, (_) {
      if (_preference != ThemePreference.auto) return;
      _setThemeMode(_scheduleResolvedMode());
    });
  }

  ThemeMode _scheduleResolvedMode() {
    final hour = _now().hour;
    final isDay = hour >= 6 && hour < 18;
    return isDay ? ThemeMode.light : ThemeMode.dark;
  }

  // ---------------------------------------------------------- Preference → mode

  void _applyPreference({bool notify = true}) {
    switch (_preference) {
      case ThemePreference.light:
        _setThemeMode(ThemeMode.light, notify: notify);
        break;
      case ThemePreference.dark:
        _setThemeMode(ThemeMode.dark, notify: notify);
        break;
      case ThemePreference.auto:
        _setThemeMode(_scheduleResolvedMode(), notify: notify);
        break;
    }
  }

  void _setThemeMode(ThemeMode mode, {bool notify = true}) {
    if (mode == _themeMode) {
      if (notify) _safeNotify();
      return;
    }
    _themeMode = mode;
    _handleBrightnessOnThemeChange();
    if (notify) _safeNotify();
  }

  // --------------------------------------------------------- Brightness override

  void _handleBrightnessOnThemeChange() {
    if (_themeMode == ThemeMode.light) {
      _maybeApplyBrightnessOverride();
    } else {
      // Entering dark (or system) — restore if we had an override.
      unawaited(_restoreBrightness());
    }
  }

  void _maybeApplyBrightnessOverride() {
    if (!_drillContextActive) return;
    if (_themeMode != ThemeMode.light) return;
    if (_overrideApplied) return;
    unawaited(_applyBrightnessOverride());
  }

  Future<void> _applyBrightnessOverride() async {
    try {
      _capturedBrightness ??= await _brightness.current;
      await _brightness.setBrightness(_maxBrightness);
      _overrideApplied = true;
    } catch (_) {
      // Brightness plugin unavailable — silently skip, not worth a toast.
    }
  }

  Future<void> _restoreBrightness() async {
    if (!_overrideApplied) return;
    final prior = _capturedBrightness;
    _overrideApplied = false;
    if (prior == null) return;
    try {
      await _brightness.setBrightness(prior);
    } catch (_) {
      // Best-effort restore.
    }
  }

  // ------------------------------------------------------------- Lifecycle

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      unawaited(_restoreBrightness());
    } else if (state == AppLifecycleState.resumed) {
      // Re-evaluate the schedule in case the clock crossed 06:00 / 18:00
      // while the app was backgrounded, then restore brightness if needed.
      if (_preference == ThemePreference.auto) {
        _setThemeMode(_scheduleResolvedMode());
      }
      _maybeApplyBrightnessOverride();
    }
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }
}
