import 'package:hive/hive.dart';

import 'drill_preset.dart';
import 'hive_bootstrap.dart';

/// Persistence for drill presets, ambient app settings, and target names.
///
/// Owns three Hive boxes:
/// - `drill_presets`   — `Map<String, DrillPreset>` keyed by preset id
/// - `app_settings`    — scalar key/value (themeMode, toggles, default preset id)
/// - `device_pairing`  — transmitter UUID + target displayName map
///
/// No BLE or UI dependencies; safe to use in unit tests that initialise Hive
/// against a temp directory.
class PreferencesRepository {
  static const String presetsBoxName = 'drill_presets';
  static const String settingsBoxName = 'app_settings';
  static const String pairingBoxName = 'device_pairing';

  static const String _kDefaultPresetId = 'default_preset_id';
  static const String _kTargetNames = 'target_names';

  Box<DrillPreset>? _presets;
  Box<dynamic>? _settings;
  Box<dynamic>? _pairing;

  bool get isInitialized =>
      _presets != null && _settings != null && _pairing != null;

  Future<void> init() async {
    _presets ??= await openTypedBox<DrillPreset>(presetsBoxName);
    _settings ??= await Hive.openBox<dynamic>(settingsBoxName);
    _pairing ??= await Hive.openBox<dynamic>(pairingBoxName);
  }

  Future<void> close() async {
    await _presets?.close();
    await _settings?.close();
    await _pairing?.close();
    _presets = null;
    _settings = null;
    _pairing = null;
  }

  // ---------------------------------------------------------------- Presets

  Future<List<DrillPreset>> listPresets() async {
    final box = _requirePresets();
    return box.values.toList(growable: false);
  }

  Future<DrillPreset?> getPreset(String id) async {
    return _requirePresets().get(id);
  }

  Future<void> savePreset(DrillPreset preset) async {
    await _requirePresets().put(preset.id, preset);
  }

  Future<void> deletePreset(String id) async {
    await _requirePresets().delete(id);
  }

  Future<void> setDefaultPresetId(String? id) async {
    final box = _requireSettings();
    if (id == null) {
      await box.delete(_kDefaultPresetId);
    } else {
      await box.put(_kDefaultPresetId, id);
    }
  }

  Future<String?> getDefaultPresetId() async {
    final value = _requireSettings().get(_kDefaultPresetId);
    return value is String ? value : null;
  }

  // ----------------------------------------------------------- App settings

  /// Reads a scalar setting by [key]. Returns null when missing or when the
  /// stored type does not match [T].
  Future<T?> getSetting<T>(String key) async {
    final value = _requireSettings().get(key);
    if (value is T) return value;
    return null;
  }

  /// Writes a scalar setting. Passing null removes the key.
  Future<void> setSetting<T>(String key, T value) async {
    final box = _requireSettings();
    if (value == null) {
      await box.delete(key);
    } else {
      await box.put(key, value);
    }
  }

  // ----------------------------------------------------------- Target names

  Future<Map<int, String>> getTargetNames() async {
    final raw = _requirePairing().get(_kTargetNames);
    if (raw is! Map) return <int, String>{};
    return raw.map<int, String>((key, value) {
      final id = key is int ? key : int.tryParse('$key') ?? -1;
      return MapEntry(id, '$value');
    })..removeWhere((k, _) => k < 0);
  }

  /// Set or clear the display name for [targetId].
  /// Passing a null [displayName] (or an empty string) removes the entry.
  Future<void> setTargetName(int targetId, String? displayName) async {
    final box = _requirePairing();
    final current = Map<String, String>.from(
      (box.get(_kTargetNames) as Map?) ?? <String, String>{},
    );
    final key = targetId.toString();
    if (displayName == null || displayName.isEmpty) {
      current.remove(key);
    } else {
      current[key] = displayName;
    }
    await box.put(_kTargetNames, current);
  }

  // ----------------------------------------------------------------- Guards

  Box<DrillPreset> _requirePresets() {
    final box = _presets;
    if (box == null) {
      throw StateError('PreferencesRepository.init() must be called first');
    }
    return box;
  }

  Box<dynamic> _requireSettings() {
    final box = _settings;
    if (box == null) {
      throw StateError('PreferencesRepository.init() must be called first');
    }
    return box;
  }

  Box<dynamic> _requirePairing() {
    final box = _pairing;
    if (box == null) {
      throw StateError('PreferencesRepository.init() must be called first');
    }
    return box;
  }
}
