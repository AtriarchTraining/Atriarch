import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper over shared_preferences for UI-adjacent settings.
/// Domain data (shooters, sessions, templates) lives in SQLite.
class PreferencesRepository {
  static const String _kDefaultPresetId = 'default_preset_id';
  static const String _kTargetNames = 'target_names';
  static const String _kRemovedTargetIds = 'removed_target_ids';
  static const String _kOnboardingComplete = 'onboarding_complete';
  static const String _kLastRangeActivity = 'last_range_activity_ms';
  static const String _kReadyAudioEnabled = 'ready_audio_enabled';
  static const String _kReadyAudioVolume = 'ready_audio_volume';
  static const String _kVisitStart = 'range_visit_start_ms';
  static const String _kSkipMoveConfirmation = 'skip_move_confirmation';

  final SharedPreferences _prefs;
  PreferencesRepository(this._prefs);

  // --- default preset id ---
  Future<String?> getDefaultPresetId() async =>
      _prefs.getString(_kDefaultPresetId);

  Future<void> setDefaultPresetId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kDefaultPresetId);
    } else {
      await _prefs.setString(_kDefaultPresetId, id);
    }
  }

  // --- target names (Map<int,String>) ---
  Future<Map<int, String>> getTargetNames() async {
    final raw = _prefs.getString(_kTargetNames);
    if (raw == null || raw.isEmpty) return <int, String>{};
    final decoded = json.decode(raw);
    if (decoded is! Map) return <int, String>{};
    final result = <int, String>{};
    decoded.forEach((k, v) {
      final id = k is int ? k : int.tryParse('$k') ?? -1;
      if (id >= 0) result[id] = '$v';
    });
    return result;
  }

  Future<void> setTargetName(int targetId, String? displayName) async {
    final current = Map<String, String>.from(
      (json.decode(_prefs.getString(_kTargetNames) ?? '{}') as Map)
          .map((k, v) => MapEntry('$k', '$v')),
    );
    final key = targetId.toString();
    if (displayName == null || displayName.isEmpty) {
      current.remove(key);
    } else {
      current[key] = displayName;
    }
    if (current.isEmpty) {
      await _prefs.remove(_kTargetNames);
    } else {
      await _prefs.setString(_kTargetNames, json.encode(current));
    }
  }

  // --- removed target ids (Set<int>) ---
  Future<Set<int>> getRemovedTargetIds() async {
    final raw = _prefs.getString(_kRemovedTargetIds);
    if (raw == null || raw.isEmpty) return <int>{};
    return raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
  }

  Future<void> setRemovedTargetIds(Set<int> ids) async {
    if (ids.isEmpty) {
      await _prefs.remove(_kRemovedTargetIds);
    } else {
      final sorted = ids.toList()..sort();
      await _prefs.setString(_kRemovedTargetIds, sorted.join(','));
    }
  }

  // --- onboarding flag ---
  Future<bool> isOnboardingComplete() async =>
      _prefs.getBool(_kOnboardingComplete) ?? false;

  Future<void> setOnboardingComplete(bool v) async =>
      _prefs.setBool(_kOnboardingComplete, v);

  // --- range-session activity timestamp ---
  /// Stamped on drill start and end. RangeSessionView uses this to compute
  /// the visible-drills cutoff (>=8h gap resets the view).
  Future<DateTime?> getLastRangeActivity() async {
    final ms = _prefs.getInt(_kLastRangeActivity);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastRangeActivity(DateTime t) async =>
      _prefs.setInt(_kLastRangeActivity, t.millisecondsSinceEpoch);

  Future<void> clearLastRangeActivity() async =>
      _prefs.remove(_kLastRangeActivity);

  /// The moment the current range visit started. Set on the first activity
  /// following a >=8h gap (or on cold-start). [RangeSessionView.listCurrent]
  /// uses this as its cutoff so all drills of the visit stay visible even
  /// as activity heartbeats advance [getLastRangeActivity].
  Future<DateTime?> getVisitStart() async {
    final ms = _prefs.getInt(_kVisitStart);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setVisitStart(DateTime t) async =>
      _prefs.setInt(_kVisitStart, t.millisecondsSinceEpoch);

  Future<void> clearVisitStart() async => _prefs.remove(_kVisitStart);

  // --- ready audio ---
  /// Whether the chime plays on discovery-complete. Defaults to true (on).
  Future<bool> isReadyAudioEnabled() async =>
      _prefs.getBool(_kReadyAudioEnabled) ?? true;

  Future<void> setReadyAudioEnabled(bool v) async =>
      _prefs.setBool(_kReadyAudioEnabled, v);

  /// Volume in [0, 1]. Defaults to 1.0. Out-of-range values are clamped.
  Future<double> getReadyAudioVolume() async =>
      _prefs.getDouble(_kReadyAudioVolume) ?? 1.0;

  Future<void> setReadyAudioVolume(double v) async {
    final clamped = v.clamp(0.0, 1.0);
    await _prefs.setDouble(_kReadyAudioVolume, clamped);
  }

  // --- skip cross-group move confirmation dialog ---
  Future<bool> getSkipMoveConfirmation() async =>
      _prefs.getBool(_kSkipMoveConfirmation) ?? false;

  Future<void> setSkipMoveConfirmation(bool v) async =>
      _prefs.setBool(_kSkipMoveConfirmation, v);
}
