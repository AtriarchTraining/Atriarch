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
  static const String _kRemovedTargetIds = 'removed_target_ids';

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

  /// Returns every preset in the box, sorted alphabetically by `name`
  /// (case-insensitive). Gate 2 #14: a stable order makes the preset dropdown
  /// predictable, and alpha-sort is the natural user-facing ordering (vs raw
  /// Hive insertion order, which has no meaning).
  Future<List<DrillPreset>> listPresets() async {
    final box = _requirePresets();
    final all = box.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List<DrillPreset>.unmodifiable(all);
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
    if (id == null) {
      await removeSetting(_kDefaultPresetId);
    } else {
      await setSetting<String>(_kDefaultPresetId, id);
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

  /// Writes a non-null scalar setting. Use [removeSetting] to delete a key.
  Future<void> setSetting<T extends Object>(String key, T value) async {
    await _requireSettings().put(key, value);
  }

  /// Removes a scalar setting. No-op when the key is missing.
  Future<void> removeSetting(String key) async {
    await _requireSettings().delete(key);
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

  // ------------------------------------------------------- Removed target ids

  /// Soft-deleted target ids. Hidden from the chip list unless the user
  /// toggles "Show removed" in the AppBar overflow (addendum §4.B).
  /// Stored as a comma-separated string in the `app_settings` box so Hive
  /// can round-trip it without the `List<dynamic>` type-strictness gotcha.
  Future<Set<int>> getRemovedTargetIds() async {
    final raw = _requireSettings().get(_kRemovedTargetIds);
    if (raw is! String || raw.isEmpty) return <int>{};
    return raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
  }

  Future<void> setRemovedTargetIds(Set<int> ids) async {
    final box = _requireSettings();
    if (ids.isEmpty) {
      await box.delete(_kRemovedTargetIds);
    } else {
      final sorted = ids.toList()..sort();
      await box.put(_kRemovedTargetIds, sorted.join(','));
    }
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
