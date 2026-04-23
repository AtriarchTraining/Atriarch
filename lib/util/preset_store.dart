import 'package:flutter/foundation.dart';

import '../models/drill_config.dart';

/// Preset store — Phase-3 TODO stub.
///
/// Gate-2 shipped a ChangeNotifier layered over a Hive
/// `PreferencesRepository` + `DrillPreset`, both deleted in the Stage-3
/// merge. The replacement is [DrillTemplateRepository] over the SQLite
/// `drill_templates` table plus the `default_preset_id` key in
/// `shared_preferences`.
///
/// Phase-3 Task 3.x rewires the Program A/B setup screens against the new
/// data layer (see `docs/superpowers/plans/2026-04-23-stage-3-tdd-phases-2-5.md`
/// Task 3.2). This stub keeps [PresetStore] importable so any stale callers
/// inside `lib/widgets/preset_row.dart` compile during Phase-2 exit.
class PresetStore extends ChangeNotifier {
  PresetStore({
    required this.programType,
  });

  final ProgramType programType;

  // Minimal shape so preset_row.dart compiles without surfacing runtime
  // state. All values are placeholders — no data persists through this stub.
  List<Object?> get presets => const <Object?>[];
  Object? get selectedPreset => null;
  bool get isModified => false;

  Future<void> load() async {}
  Future<void> selectById(String? id) async {}
  Future<void> saveAs(String name, DrillConfig config) async {}
  Future<void> overwriteSelected(DrillConfig config) async {}
  Future<void> delete(String id) async {}
  void setLiveConfig(DrillConfig config) {}
}
