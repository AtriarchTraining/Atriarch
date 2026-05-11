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
  bool _skipMoveConfirmation = false;

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

  @override
  Future<bool> getSkipMoveConfirmation() async => _skipMoveConfirmation;

  @override
  Future<void> setSkipMoveConfirmation(bool v) async {
    _skipMoveConfirmation = v;
  }

  // --- target groups ---
  final Map<int, int> _targetGroups = {};

  @override
  Future<Map<int, int>> getTargetGroups() async => Map.from(_targetGroups);

  @override
  Future<void> setTargetGroup(int targetId, int? groupNumber) async {
    if (groupNumber == null) {
      _targetGroups.remove(targetId);
    } else {
      _targetGroups[targetId] = groupNumber;
    }
  }

  // --- target group labels ---
  final Map<int, String> _targetGroupLabels = {};

  @override
  Future<Map<int, String>> getTargetGroupLabels() async =>
      Map.from(_targetGroupLabels);

  @override
  Future<void> setTargetGroupLabel(int groupNumber, String? label) async {
    if (label == null || label.isEmpty) {
      _targetGroupLabels.remove(groupNumber);
    } else {
      _targetGroupLabels[groupNumber] = label;
    }
  }

  // --- target group order ---
  List<int> _targetGroupOrder = [];

  @override
  Future<List<int>> getTargetGroupOrder() async =>
      List.from(_targetGroupOrder);

  @override
  Future<void> setTargetGroupOrder(List<int> order) async {
    _targetGroupOrder = List.from(order);
  }
}
