import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/drill_config.dart';
import '../models/target_group.dart';
import 'drill_preset.dart';
import 'session_summary.dart';

/// One-time Hive setup for the app. Call `await initHive()` before building
/// [AppState] / running the app.
///
/// Registers all adapters but does NOT open boxes — each repository opens
/// its own in [init] so tests and bootstraps stay decoupled.
Future<void> initHive() async {
  await Hive.initFlutter();
  registerAtriarchAdapters();
}

/// Registers every adapter used by the app. Safe to call multiple times —
/// Hive ignores duplicate registrations for the same typeId+adapter.
///
/// Split out from [initHive] so unit tests (which use `Hive.init(tempDir)`
/// instead of `Hive.initFlutter()`) can share the adapter list.
void registerAtriarchAdapters() {
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(ProgramTypeAdapter());
  }
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(DrillConfigAdapter());
  }
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(TargetGroupAdapter());
  }
  if (!Hive.isAdapterRegistered(10)) {
    Hive.registerAdapter(DrillPresetAdapter());
  }
  if (!Hive.isAdapterRegistered(11)) {
    Hive.registerAdapter(SessionSummaryAdapter());
  }
}

/// Signature for a versioned migration closure.
///
/// Each migration is identified by a `"boxName:fromVersion"` key and returns
/// after rewriting entries in-place so they satisfy the current schema.
typedef HiveMigration = FutureOr<void> Function(Box<dynamic> box);

/// Migration table. v1 is the initial release, so this map is empty — the
/// scaffold exists so future schema bumps have a home without refactoring
/// every repository.
///
/// Key format: `"<boxName>:<fromVersion>"`. When a record with a lower
/// `version` field is found, [openTypedBox] runs the matching closure.
final Map<String, HiveMigration> atriarchMigrations =
    <String, HiveMigration>{};

/// Opens a typed box and runs any registered migrations for records whose
/// `version` field is lower than the target schema version.
///
/// For v1 the migrations map is empty, so this is a thin wrapper over
/// [Hive.openBox]. It exists so Wave 2/3 (and beyond) can evolve schemas
/// without repositories growing their own migration logic.
Future<Box<T>> openTypedBox<T>(
  String name, {
  int currentVersion = 1,
  Map<String, HiveMigration>? migrations,
}) async {
  final box = await Hive.openBox<T>(name);
  final table = migrations ?? atriarchMigrations;

  // Nothing to do until we have a v2. The loop is harmless and keeps the
  // API stable for later waves.
  if (table.isEmpty) return box;

  for (final key in box.keys) {
    final value = box.get(key);
    if (value == null) continue;

    final dynamic dynVal = value;
    int recordVersion;
    try {
      recordVersion = (dynVal.version as int?) ?? 1;
    } catch (_) {
      // Not a versioned record — skip.
      continue;
    }

    while (recordVersion < currentVersion) {
      final migration = table['$name:$recordVersion'];
      if (migration == null) break;
      await migration(box);
      recordVersion += 1;
    }
  }

  return box;
}
