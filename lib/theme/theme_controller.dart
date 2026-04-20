import 'dart:async';

import 'package:flutter/material.dart';
import 'package:light_sensor/light_sensor.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../data/preferences_repository.dart';

/// User preference for theme selection.
///
/// - [auto] — lux-driven (ambient light sensor) with time-of-day fallback
///   when the sensor is unavailable.
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
/// Lux hysteresis (§7.2):
/// - lux > 1000 sustained ≥2s → LIGHT
/// - lux < 200 sustained ≥2s → DARK
/// - in-between or flapping → hold
///
/// When preference is [ThemePreference.auto] and the `light_sensor` plugin
/// is unavailable, fall back to a local-time schedule: 06:00–18:00 = LIGHT,
/// otherwise DARK. [sensorUnavailable] flips true exactly once per session
/// so the UI can surface a one-shot notice.
///
/// Brightness override (§Outdoor rule): only when [setDrillContextActive]
/// is true AND resolved theme is LIGHT. Captures the prior brightness once
/// per override so `restore` is lossless. On lifecycle `paused`/`inactive`
/// the override is released; on resume + still in LIGHT + still in context,
/// it re-applies.
class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  static const String preferenceSettingKey = 'theme_preference';
  static const int _lightLuxThreshold = 1000;
  static const int _darkLuxThreshold = 200;
  static const Duration _hysteresisWindow = Duration(seconds: 2);
  static const double _maxBrightness = 1.0;

  final PreferencesRepository _preferences;
  final Stream<int>? _luxStreamOverride;
  final BrightnessController _brightness;
  final WidgetsBinding _binding;
  final DateTime Function() _now;

  ThemeController({
    required PreferencesRepository preferences,
    Stream<int>? luxStreamOverride,
    BrightnessController? brightnessOverride,
    WidgetsBinding? binding,
    DateTime Function()? now,
  })  : _preferences = preferences,
        _luxStreamOverride = luxStreamOverride,
        _brightness = brightnessOverride ?? _RealBrightnessController(),
        _binding = binding ?? WidgetsBinding.instance,
        _now = now ?? DateTime.now;

  ThemePreference _preference = ThemePreference.auto;
  ThemeMode _themeMode = ThemeMode.light;
  bool _sensorUnavailable = false;
  bool _drillContextActive = false;

  // Lux hysteresis state. `_pendingZone` is the zone the lux stream has been
  // in since a timer was started. When the timer fires (after
  // `_hysteresisWindow`), the zone "wins" and becomes the resolved theme.
  _LuxZone _pendingZone = _LuxZone.hold;
  StreamSubscription<int>? _luxSub;
  Timer? _hysteresisTimer;

  // Brightness-override bookkeeping.
  double? _capturedBrightness;
  bool _overrideApplied = false;

  bool _disposed = false;

  ThemeMode get themeMode => _themeMode;
  ThemePreference get preference => _preference;
  bool get sensorUnavailable => _sensorUnavailable;
  bool get drillContextActive => _drillContextActive;

  /// Load persisted preference, subscribe to lux stream, start listening for
  /// app lifecycle changes. Safe to call once per app session.
  Future<void> init() async {
    _binding.addObserver(this);
    final stored =
        await _preferences.getSetting<String>(preferenceSettingKey);
    _preference = ThemePreference.fromKey(stored);
    _applyPreference(notify: false);

    // Only subscribe to lux when the user is in auto. If they later switch
    // back to auto, `setPreference` will (re)subscribe.
    if (_preference == ThemePreference.auto) {
      _subscribeLux();
    }
  }

  /// Explicit cleanup; [ChangeNotifier.dispose] is still called.
  @override
  void dispose() {
    _disposed = true;
    _binding.removeObserver(this);
    _hysteresisTimer?.cancel();
    _hysteresisTimer = null;
    unawaited(_luxSub?.cancel());
    _luxSub = null;
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
      _subscribeLux();
    } else {
      unawaited(_luxSub?.cancel());
      _luxSub = null;
      _hysteresisTimer?.cancel();
      _hysteresisTimer = null;
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

  // ------------------------------------------------------------------- Lux

  void _subscribeLux() {
    _luxSub?.cancel();
    _hysteresisTimer?.cancel();
    _hysteresisTimer = null;
    _pendingZone = _LuxZone.hold;

    final stream = _luxStreamOverride ?? LightSensor.luxStream();
    try {
      _luxSub = stream.listen(
        _onLux,
        onError: (Object _) => _handleSensorUnavailable(),
      );
    } catch (_) {
      _handleSensorUnavailable();
    }
  }

  void _onLux(int lux) {
    final zone = _zoneForLux(lux);
    if (zone == _LuxZone.hold) {
      // Mid-zone reading — reset pending timer; whatever was building loses.
      _pendingZone = _LuxZone.hold;
      _hysteresisTimer?.cancel();
      _hysteresisTimer = null;
      return;
    }
    if (zone != _pendingZone) {
      _pendingZone = zone;
      _hysteresisTimer?.cancel();
      _hysteresisTimer = Timer(_hysteresisWindow, _commitPendingZone);
    }
    // Same zone continuing — timer already running, nothing to do.
  }

  void _commitPendingZone() {
    if (_preference != ThemePreference.auto) return;
    final target = switch (_pendingZone) {
      _LuxZone.light => ThemeMode.light,
      _LuxZone.dark => ThemeMode.dark,
      _LuxZone.hold => _themeMode,
    };
    _setThemeMode(target);
  }

  _LuxZone _zoneForLux(int lux) {
    if (lux > _lightLuxThreshold) return _LuxZone.light;
    if (lux < _darkLuxThreshold) return _LuxZone.dark;
    return _LuxZone.hold;
  }

  void _handleSensorUnavailable() {
    if (_sensorUnavailable) return;
    _sensorUnavailable = true;
    _luxSub?.cancel();
    _luxSub = null;
    if (_preference == ThemePreference.auto) {
      _setThemeMode(_scheduleResolvedMode());
    } else {
      _safeNotify();
    }
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
        if (_sensorUnavailable) {
          _setThemeMode(_scheduleResolvedMode(), notify: notify);
        } else {
          // Hold current until first lux reading arrives.
          if (notify) _safeNotify();
        }
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
      _maybeApplyBrightnessOverride();
    }
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }
}

enum _LuxZone { light, dark, hold }
