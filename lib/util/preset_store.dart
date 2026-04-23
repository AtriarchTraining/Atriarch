import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/drill_preset.dart';
import '../data/preferences_repository.dart';
import '../models/drill_config.dart';

/// Narrow ChangeNotifier that owns the in-memory snapshot of presets for a
/// specific [ProgramType], plus the currently-selected preset id and a
/// "live config" (the setup screen's working draft) used to compute
/// [isModified].
///
/// Lives OUTSIDE global AppState so each Program Setup screen can scope its
/// own preset state without polluting other screens. A fresh store is built
/// in the screen's `initState` and disposed in `dispose`.
class PresetStore extends ChangeNotifier {
  PresetStore({
    required PreferencesRepository repository,
    required ProgramType programType,
    Uuid? uuid,
    DateTime Function()? clock,
  })  : _repository = repository,
        _programType = programType,
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now;

  final PreferencesRepository _repository;
  final ProgramType _programType;
  final Uuid _uuid;
  final DateTime Function() _clock;

  List<DrillPreset> _presets = const <DrillPreset>[];
  String? _selectedId;
  String? _defaultId;
  DrillConfig? _liveConfig;
  bool _initialized = false;

  /// Programs this store is scoped to. The dropdown filters by this.
  ProgramType get programType => _programType;

  /// Snapshot of presets matching [programType], alpha-sorted by name.
  List<DrillPreset> get presets => _presets;

  /// Id of the preset the setup screen is currently "loaded from".
  /// Null when no preset is selected.
  String? get selectedPresetId => _selectedId;

  /// Id of the user's default preset across ALL programs, if any. The
  /// Program Setup screen only auto-loads it when the program type matches.
  String? get defaultPresetId => _defaultId;

  /// True when [_liveConfig] has drifted from the selected preset's stored
  /// config (via [DrillConfig.sameFields]). False when no preset selected
  /// or no live config has been pushed yet.
  bool get isModified {
    final selId = _selectedId;
    final live = _liveConfig;
    if (selId == null || live == null) return false;
    final preset = _presetById(selId);
    if (preset == null) return false;
    return !preset.config.sameFields(live);
  }

  /// True after [init] completes. Used by UI to defer rendering until the
  /// first preset list has been pulled.
  bool get isInitialized => _initialized;

  /// The most recent live config pushed via [setLiveConfig]. Null until the
  /// owning screen has pushed at least once. Exposed so the preset row's
  /// Save… sheet can capture the current form state without the screen
  /// having to marshal it through a callback.
  DrillConfig? get liveConfig => _liveConfig;

  /// Loads the filtered preset list and the default-preset id. If the
  /// default preset matches this store's [programType], it is auto-selected.
  Future<void> init() async {
    await _reload();
    _defaultId = await _repository.getDefaultPresetId();
    final def = _defaultId;
    if (def != null) {
      final match = _presetById(def);
      if (match != null && match.config.programType == _programType) {
        _selectedId = def;
      }
    }
    _initialized = true;
    notifyListeners();
  }

  /// Called by the setup screen every time the form values change. Does NOT
  /// persist anything — it only feeds [isModified].
  void setLiveConfig(DrillConfig live) {
    _liveConfig = live;
    notifyListeners();
  }

  /// Selects [id] (or clears the selection when `null`). Safe to pass an id
  /// that isn't in [presets] — it becomes a no-op.
  Future<void> selectPreset(String? id) async {
    if (id == null) {
      if (_selectedId == null) return;
      _selectedId = null;
      notifyListeners();
      return;
    }
    final match = _presetById(id);
    if (match == null) return;
    if (match.config.programType != _programType) return;
    _selectedId = id;
    notifyListeners();
  }

  /// Persists a brand-new preset with [name] + [config], reloads the list,
  /// and selects it. Returns the newly-created preset.
  Future<DrillPreset> savePresetAsNew(String name, DrillConfig config) async {
    final now = _clock();
    final preset = DrillPreset(
      id: _uuid.v4(),
      name: name,
      createdAt: now,
      updatedAt: now,
      config: config.copyWithFields(programType: _programType),
    );
    await _repository.savePreset(preset);
    await _reload();
    _selectedId = preset.id;
    notifyListeners();
    return preset;
  }

  /// Overwrites the selected preset's `config` with [config] and bumps
  /// `updatedAt`. No-op when nothing is selected.
  Future<void> overwriteSelected(DrillConfig config) async {
    final selId = _selectedId;
    if (selId == null) return;
    final existing = _presetById(selId);
    if (existing == null) return;
    final updated = DrillPreset(
      id: existing.id,
      name: existing.name,
      createdAt: existing.createdAt,
      updatedAt: _clock(),
      config: config.copyWithFields(programType: _programType),
      version: existing.version,
    );
    await _repository.savePreset(updated);
    await _reload();
    notifyListeners();
  }

  /// Renames the selected preset. No-op when nothing is selected or [newName]
  /// is empty.
  Future<void> renameSelected(String newName) async {
    final selId = _selectedId;
    if (selId == null) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final existing = _presetById(selId);
    if (existing == null) return;
    final renamed = DrillPreset(
      id: existing.id,
      name: trimmed,
      createdAt: existing.createdAt,
      updatedAt: _clock(),
      config: existing.config,
      version: existing.version,
    );
    await _repository.savePreset(renamed);
    await _reload();
    notifyListeners();
  }

  /// Deletes the selected preset. Clears the selection. If the deleted
  /// preset was also the default, clears the stored default id too.
  Future<void> deleteSelected() async {
    final selId = _selectedId;
    if (selId == null) return;
    await _repository.deletePreset(selId);
    if (_defaultId == selId) {
      await _repository.setDefaultPresetId(null);
      _defaultId = null;
    }
    _selectedId = null;
    await _reload();
    notifyListeners();
  }

  /// Creates a copy of the selected preset with a new UUID and name suffix
  /// " copy". Selects the copy. Does NOT mark it default.
  Future<DrillPreset> duplicateSelected() async {
    final selId = _selectedId;
    if (selId == null) {
      throw StateError('duplicateSelected called with no selection');
    }
    final existing = _presetById(selId);
    if (existing == null) {
      throw StateError('duplicateSelected: selected preset vanished');
    }
    final now = _clock();
    final dup = DrillPreset(
      id: _uuid.v4(),
      name: '${existing.name} copy',
      createdAt: now,
      updatedAt: now,
      config: existing.config.copyWithFields(),
    );
    await _repository.savePreset(dup);
    await _reload();
    _selectedId = dup.id;
    notifyListeners();
    return dup;
  }

  /// Marks the selected preset as the app-wide default. No-op when no
  /// selection.
  Future<void> setSelectedAsDefault() async {
    final selId = _selectedId;
    if (selId == null) return;
    await _repository.setDefaultPresetId(selId);
    _defaultId = selId;
    notifyListeners();
  }

  Future<void> _reload() async {
    final all = await _repository.listPresets();
    _presets = List<DrillPreset>.unmodifiable(
      all.where((p) => p.config.programType == _programType),
    );
  }

  DrillPreset? _presetById(String id) {
    for (final p in _presets) {
      if (p.id == id) return p;
    }
    return null;
  }
}
