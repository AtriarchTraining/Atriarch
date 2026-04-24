import 'package:atriarch/services/preferences_repository.dart';

/// In-memory fake for widget tests that mount a screen requiring
/// [PreferencesRepository]. Mirrors the real repo's defaults so
/// `AppState.hydratePreferences()` produces identical state.
class FakePreferencesRepository implements PreferencesRepository {
  String? _defaultPresetId;
  final Map<int, String> _targetNames = {};
  Set<int> _removedTargetIds = {};
  bool _onboardingComplete = false;
  DateTime? _lastRangeActivity;
  DateTime? _visitStart;
  bool _readyAudioEnabled = true;
  double _readyAudioVolume = 1.0;

  @override
  Future<String?> getDefaultPresetId() async => _defaultPresetId;

  @override
  Future<void> setDefaultPresetId(String? id) async => _defaultPresetId = id;

  @override
  Future<Map<int, String>> getTargetNames() async => Map.from(_targetNames);

  @override
  Future<void> setTargetName(int targetId, String? displayName) async {
    if (displayName == null || displayName.isEmpty) {
      _targetNames.remove(targetId);
    } else {
      _targetNames[targetId] = displayName;
    }
  }

  @override
  Future<Set<int>> getRemovedTargetIds() async => Set.from(_removedTargetIds);

  @override
  Future<void> setRemovedTargetIds(Set<int> ids) async =>
      _removedTargetIds = Set.from(ids);

  @override
  Future<bool> isOnboardingComplete() async => _onboardingComplete;

  @override
  Future<void> setOnboardingComplete(bool v) async => _onboardingComplete = v;

  @override
  Future<DateTime?> getLastRangeActivity() async => _lastRangeActivity;

  @override
  Future<void> setLastRangeActivity(DateTime t) async =>
      _lastRangeActivity = t;

  @override
  Future<void> clearLastRangeActivity() async => _lastRangeActivity = null;

  @override
  Future<DateTime?> getVisitStart() async => _visitStart;

  @override
  Future<void> setVisitStart(DateTime t) async => _visitStart = t;

  @override
  Future<void> clearVisitStart() async => _visitStart = null;

  @override
  Future<bool> isReadyAudioEnabled() async => _readyAudioEnabled;

  @override
  Future<void> setReadyAudioEnabled(bool v) async => _readyAudioEnabled = v;

  @override
  Future<double> getReadyAudioVolume() async => _readyAudioVolume;

  @override
  Future<void> setReadyAudioVolume(double v) async =>
      _readyAudioVolume = v.clamp(0.0, 1.0);
}
