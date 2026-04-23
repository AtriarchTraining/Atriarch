import 'package:flutter/material.dart';

import '../util/preset_store.dart';

/// PresetRow — Phase-3 TODO stub.
///
/// Gate-2 shipped a preset dropdown + Save…/overflow row pinned above the
/// Program Setup form. Its implementation depended on the Hive `DrillPreset`
/// and the gate-2 Hive `PreferencesRepository`, both removed in the
/// Stage-3 merge. Phase-3 Task 3.2 rebuilds the row against
/// [DrillTemplateRepository] + `shared_preferences` in tactical styling.
///
/// This stub keeps the public type importable so any screen files that still
/// reference it (the setup screens are rewritten in Phase 3 anyway) compile
/// cleanly at Phase 2 exit.
class PresetRow extends StatelessWidget {
  const PresetRow({
    super.key,
    required this.store,
    required this.onPresetLoaded,
  });

  final PresetStore store;
  final VoidCallback onPresetLoaded;

  @override
  Widget build(BuildContext context) {
    // Intentionally minimal — real UI lands in Phase 3.
    return const SizedBox.shrink();
  }
}
