import 'dart:io';

import 'package:atriarch/data/drill_preset.dart';
import 'package:atriarch/data/hive_bootstrap.dart';
import 'package:atriarch/data/preferences_repository.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/target_group.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late PreferencesRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('atriarch_prefs_');
    Hive.init(tempDir.path);
    registerAtriarchAdapters();
    repo = PreferencesRepository();
    await repo.init();
  });

  tearDown(() async {
    await repo.close();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  DrillPreset makePreset(String id, {String name = 'Test'}) {
    return DrillPreset(
      id: id,
      name: name,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      config: DrillConfig(
        programType: ProgramType.programA,
        groups: [TargetGroup(id: 1, targetIds: [101, 102])],
        targetIds: [101, 102],
      ),
    );
  }

  test('init/close is idempotent and reports state', () async {
    expect(repo.isInitialized, isTrue);
    await repo.close();
    expect(repo.isInitialized, isFalse);
    await repo.init();
    expect(repo.isInitialized, isTrue);
  });

  test('preset CRUD round-trip', () async {
    expect(await repo.listPresets(), isEmpty);

    final p = makePreset('p1', name: 'Walk-back');
    await repo.savePreset(p);

    final all = await repo.listPresets();
    expect(all, hasLength(1));
    expect(all.first.name, 'Walk-back');
    expect(all.first.config.programType, ProgramType.programA);
    expect(all.first.config.targetIds, [101, 102]);

    final fetched = await repo.getPreset('p1');
    expect(fetched, isNotNull);
    expect(fetched!.id, 'p1');

    // Upsert semantics: saving the same id overwrites.
    final p2 = makePreset('p1', name: 'Walk-back v2');
    await repo.savePreset(p2);
    expect((await repo.getPreset('p1'))!.name, 'Walk-back v2');
    expect(await repo.listPresets(), hasLength(1));

    await repo.deletePreset('p1');
    expect(await repo.getPreset('p1'), isNull);
    expect(await repo.listPresets(), isEmpty);
  });

  test('default preset id round-trip', () async {
    expect(await repo.getDefaultPresetId(), isNull);
    await repo.setDefaultPresetId('p1');
    expect(await repo.getDefaultPresetId(), 'p1');
    await repo.setDefaultPresetId(null);
    expect(await repo.getDefaultPresetId(), isNull);
  });

  test('scalar settings getSetting/setSetting/removeSetting', () async {
    await repo.setSetting<bool>('readyAudioEnabled', true);
    await repo.setSetting<double>('volume', 0.75);
    await repo.setSetting<String>('themeMode', 'dark');

    expect(await repo.getSetting<bool>('readyAudioEnabled'), true);
    expect(await repo.getSetting<double>('volume'), 0.75);
    expect(await repo.getSetting<String>('themeMode'), 'dark');

    // Wrong type read returns null.
    expect(await repo.getSetting<int>('readyAudioEnabled'), isNull);
    // Missing key returns null.
    expect(await repo.getSetting<String>('nonexistent'), isNull);

    // removeSetting deletes the key; subsequent read returns null.
    await repo.removeSetting('themeMode');
    expect(await repo.getSetting<String>('themeMode'), isNull);
    // removeSetting is a no-op on missing keys.
    await repo.removeSetting('never_set');
  });

  test('target names round-trip (addendum §4.B)', () async {
    expect(await repo.getTargetNames(), isEmpty);

    await repo.setTargetName(1, 'Flipper');
    await repo.setTargetName(3, 'Runner');

    var names = await repo.getTargetNames();
    expect(names, {1: 'Flipper', 3: 'Runner'});

    // Overwrite.
    await repo.setTargetName(1, 'Flipper-B');
    names = await repo.getTargetNames();
    expect(names[1], 'Flipper-B');

    // Null removes.
    await repo.setTargetName(1, null);
    names = await repo.getTargetNames();
    expect(names.containsKey(1), isFalse);
    expect(names[3], 'Runner');

    // Empty string also removes.
    await repo.setTargetName(3, '');
    expect(await repo.getTargetNames(), isEmpty);
  });

  test('removed target ids round-trip (addendum §4.B)', () async {
    expect(await repo.getRemovedTargetIds(), isEmpty);

    await repo.setRemovedTargetIds({2, 5, 11});
    expect(await repo.getRemovedTargetIds(), {2, 5, 11});

    // Overwrite shrinks the set.
    await repo.setRemovedTargetIds({5});
    expect(await repo.getRemovedTargetIds(), {5});

    // Empty clears.
    await repo.setRemovedTargetIds(<int>{});
    expect(await repo.getRemovedTargetIds(), isEmpty);
  });

  test('removed target ids survive close/reopen', () async {
    await repo.setRemovedTargetIds({3, 9});
    await repo.close();

    final reopened = PreferencesRepository();
    await reopened.init();
    expect(await reopened.getRemovedTargetIds(), {3, 9});
    await reopened.close();
  });

  test('data persists across close/reopen', () async {
    await repo.savePreset(makePreset('persist'));
    await repo.setTargetName(7, 'Lucky');
    await repo.setSetting<String>('themeMode', 'light');

    await repo.close();

    final reopened = PreferencesRepository();
    await reopened.init();
    expect(await reopened.getPreset('persist'), isNotNull);
    expect((await reopened.getTargetNames())[7], 'Lucky');
    expect(await reopened.getSetting<String>('themeMode'), 'light');
    await reopened.close();
  });

  test('methods throw before init()', () async {
    final fresh = PreferencesRepository();
    expect(fresh.listPresets, throwsA(isA<StateError>()));
  });
}
