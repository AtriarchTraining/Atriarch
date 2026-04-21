/// In-memory repository stand-ins used by [AppState.forTest] and direct
/// unit tests that don't need real Hive persistence.
///
/// These share the public surface of their Hive-backed counterparts but
/// store everything in Dart maps/lists so tests can avoid
/// `Hive.init(tempDir)` boilerplate. They intentionally skip schema
/// migration and versioning — callers that need those behaviours should
/// test against the concrete repositories.
import 'dart:async';

import 'drill_log_repository.dart';
import 'drill_preset.dart';
import 'preferences_repository.dart';
import 'session_repository.dart';
import 'session_summary.dart';

class InMemoryPreferencesRepository implements PreferencesRepository {
  final Map<String, DrillPreset> _presets = <String, DrillPreset>{};
  final Map<String, Object?> _settings = <String, Object?>{};
  final Map<int, String> _targetNames = <int, String>{};
  final Set<int> _removedTargetIds = <int>{};
  bool _initialized = false;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> init() async {
    _initialized = true;
  }

  @override
  Future<void> close() async {
    _initialized = false;
  }

  @override
  Future<List<DrillPreset>> listPresets() async =>
      _presets.values.toList(growable: false);

  @override
  Future<DrillPreset?> getPreset(String id) async => _presets[id];

  @override
  Future<void> savePreset(DrillPreset preset) async {
    _presets[preset.id] = preset;
  }

  @override
  Future<void> deletePreset(String id) async {
    _presets.remove(id);
  }

  @override
  Future<void> setDefaultPresetId(String? id) async {
    if (id == null) {
      _settings.remove('default_preset_id');
    } else {
      _settings['default_preset_id'] = id;
    }
  }

  @override
  Future<String?> getDefaultPresetId() async {
    final v = _settings['default_preset_id'];
    return v is String ? v : null;
  }

  @override
  Future<T?> getSetting<T>(String key) async {
    final v = _settings[key];
    return v is T ? v : null;
  }

  @override
  Future<void> setSetting<T extends Object>(String key, T value) async {
    _settings[key] = value;
  }

  @override
  Future<void> removeSetting(String key) async {
    _settings.remove(key);
  }

  @override
  Future<Map<int, String>> getTargetNames() async =>
      Map<int, String>.from(_targetNames);

  @override
  Future<void> setTargetName(int targetId, String? displayName) async {
    if (displayName == null || displayName.isEmpty) {
      _targetNames.remove(targetId);
    } else {
      _targetNames[targetId] = displayName;
    }
  }

  @override
  Future<Set<int>> getRemovedTargetIds() async =>
      Set<int>.from(_removedTargetIds);

  @override
  Future<void> setRemovedTargetIds(Set<int> ids) async {
    _removedTargetIds
      ..clear()
      ..addAll(ids);
  }
}

class InMemorySessionRepository implements SessionRepository {
  final List<SessionSummary> _cache = <SessionSummary>[];
  final StreamController<List<SessionSummary>> _controller =
      StreamController<List<SessionSummary>>.broadcast();
  DateTime? _sessionStart;
  bool _initialized = false;
  final DateTime Function() _clock;

  InMemorySessionRepository({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  @override
  bool get isInitialized => _initialized;

  @override
  DateTime? get sessionStart => _sessionStart;

  @override
  List<SessionSummary> get currentSessionDrills =>
      List<SessionSummary>.unmodifiable(_cache);

  @override
  Stream<List<SessionSummary>> watch() => _controller.stream;

  @override
  Future<void> init() async {
    _initialized = true;
  }

  @override
  Future<void> close() async {
    await _controller.close();
    _initialized = false;
  }

  @override
  Future<void> beginSessionIfNeeded() async {
    final now = _clock();
    final start = _sessionStart;
    final stale = start == null ||
        now.difference(start) >= SessionRepository.sessionIdleTimeout;
    if (!stale) return;
    _cache.clear();
    _sessionStart = now;
    _emit();
  }

  @override
  Future<void> appendDrill(SessionSummary summary) async {
    _cache.add(summary);
    _emit();
  }

  @override
  Future<void> clearSession() async {
    _cache.clear();
    _sessionStart = null;
    _emit();
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(List<SessionSummary>.unmodifiable(_cache));
  }
}

class InMemoryDrillLogRepository implements DrillLogRepository {
  final Map<String, String> _logs = <String, String>{};
  bool _initialized = false;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> init() async {
    _initialized = true;
  }

  @override
  Future<void> close() async {
    _initialized = false;
  }

  @override
  Future<void> writeLog(String drillId, String jsonPayload) async {
    _logs[drillId] = jsonPayload;
  }

  @override
  Future<String?> readLog(String drillId) async => _logs[drillId];

  @override
  Future<List<String>> listDrillIds() async =>
      _logs.keys.toList(growable: false);

  @override
  Future<void> deleteLog(String drillId) async {
    _logs.remove(drillId);
  }

  @override
  Future<String> exportLogToFile(String drillId) async {
    throw UnsupportedError(
      'InMemoryDrillLogRepository does not support file export. '
      'Use the concrete DrillLogRepository in tests that need this.',
    );
  }
}
