import 'package:atriarch/data/drill_preset.dart';
import 'package:atriarch/data/in_memory_repositories.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/target_group.dart';
import 'package:atriarch/util/preset_store.dart';
import 'package:flutter_test/flutter_test.dart';

DrillConfig _cfg({
  ProgramType program = ProgramType.programA,
  int iterations = 5,
  double startMin = 1.0,
}) {
  return DrillConfig(
    programType: program,
    startMin: startMin,
    startMax: 3.0,
    delayMin: 0.5,
    delayMax: 2.0,
    hitsMin: 1,
    hitsMax: 3,
    groups: [TargetGroup(id: 1, targetIds: [101])],
    targetIds: [101],
    noShootIds: const [],
    iterations: iterations,
  );
}

Future<DrillPreset> _seedPreset(
  InMemoryPreferencesRepository repo,
  String id, {
  required String name,
  ProgramType program = ProgramType.programA,
  int iterations = 5,
}) async {
  final preset = DrillPreset(
    id: id,
    name: name,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
    config: _cfg(program: program, iterations: iterations),
  );
  await repo.savePreset(preset);
  return preset;
}

void main() {
  late InMemoryPreferencesRepository repo;

  setUp(() async {
    repo = InMemoryPreferencesRepository();
    await repo.init();
  });

  test('init loads presets filtered by programType', () async {
    await _seedPreset(repo, 'a1', name: 'Alpha');
    await _seedPreset(repo, 'b1', name: 'Beta', program: ProgramType.programB);

    final storeA = PresetStore(
      repository: repo,
      programType: ProgramType.programA,
    );
    await storeA.init();
    expect(storeA.presets.map((p) => p.id), ['a1']);

    final storeB = PresetStore(
      repository: repo,
      programType: ProgramType.programB,
    );
    await storeB.init();
    expect(storeB.presets.map((p) => p.id), ['b1']);
  });

  test('init auto-selects default preset when its program matches', () async {
    await _seedPreset(repo, 'a1', name: 'Alpha');
    await repo.setDefaultPresetId('a1');

    final store = PresetStore(
      repository: repo,
      programType: ProgramType.programA,
    );
    await store.init();

    expect(store.selectedPresetId, 'a1');
    expect(store.defaultPresetId, 'a1');
  });

  test('init does NOT auto-select default when program differs', () async {
    await _seedPreset(repo, 'b1', name: 'Beta', program: ProgramType.programB);
    await repo.setDefaultPresetId('b1');

    final store = PresetStore(
      repository: repo,
      programType: ProgramType.programA,
    );
    await store.init();

    expect(store.selectedPresetId, isNull);
    expect(store.defaultPresetId, 'b1');
  });

  test('setLiveConfig + isModified round-trip', () async {
    await _seedPreset(repo, 'a1', name: 'Alpha');
    final store = PresetStore(
      repository: repo,
      programType: ProgramType.programA,
    );
    await store.init();
    await store.selectPreset('a1');

    // Same config -> not modified.
    store.setLiveConfig(_cfg());
    expect(store.isModified, isFalse);

    // Edited config -> modified.
    store.setLiveConfig(_cfg(iterations: 42));
    expect(store.isModified, isTrue);
  });

  test('savePresetAsNew persists, selects, clears modified', () async {
    final store = PresetStore(
      repository: repo,
      programType: ProgramType.programA,
    );
    await store.init();
    expect(store.presets, isEmpty);

    final live = _cfg(iterations: 7);
    store.setLiveConfig(live);
    final created = await store.savePresetAsNew('Walk-back', live);

    expect(store.presets.map((p) => p.name), ['Walk-back']);
    expect(store.selectedPresetId, created.id);
    expect(store.isModified, isFalse);
  });

  test('overwriteSelected updates config and clears modified', () async {
    await _seedPreset(repo, 'a1', name: 'Alpha');
    final store = PresetStore(
      repository: repo,
      programType: ProgramType.programA,
    );
    await store.init();
    await store.selectPreset('a1');

    final edited = _cfg(iterations: 99);
    store.setLiveConfig(edited);
    expect(store.isModified, isTrue);

    await store.overwriteSelected(edited);
    expect(store.isModified, isFalse);

    final saved = await repo.getPreset('a1');
    expect(saved!.config.iterations, 99);
  });

  test('deleteSelected removes, clears selection + default if matched',
      () async {
    await _seedPreset(repo, 'a1', name: 'Alpha');
    await repo.setDefaultPresetId('a1');
    final store = PresetStore(
      repository: repo,
      programType: ProgramType.programA,
    );
    await store.init();
    expect(store.selectedPresetId, 'a1');
    expect(store.defaultPresetId, 'a1');

    await store.deleteSelected();
    expect(store.presets, isEmpty);
    expect(store.selectedPresetId, isNull);
    expect(store.defaultPresetId, isNull);
    expect(await repo.getDefaultPresetId(), isNull);
  });

  test('deleteSelected keeps default untouched when different preset', () async {
    await _seedPreset(repo, 'a1', name: 'Alpha');
    await _seedPreset(repo, 'a2', name: 'Bravo');
    await repo.setDefaultPresetId('a2');

    final store = PresetStore(
      repository: repo,
      programType: ProgramType.programA,
    );
    await store.init();
    await store.selectPreset('a1');
    await store.deleteSelected();

    expect(store.defaultPresetId, 'a2');
    expect(await repo.getDefaultPresetId(), 'a2');
  });

  test('duplicateSelected copies, selects new, not default', () async {
    await _seedPreset(repo, 'a1', name: 'Alpha');
    final store = PresetStore(
      repository: repo,
      programType: ProgramType.programA,
    );
    await store.init();
    await store.selectPreset('a1');

    final dup = await store.duplicateSelected();

    expect(dup.id, isNot('a1'));
    expect(dup.name, 'Alpha copy');
    expect(store.selectedPresetId, dup.id);
    expect(store.defaultPresetId, isNull);
  });

  test('setSelectedAsDefault flips the default id', () async {
    await _seedPreset(repo, 'a1', name: 'Alpha');
    final store = PresetStore(
      repository: repo,
      programType: ProgramType.programA,
    );
    await store.init();
    await store.selectPreset('a1');

    expect(store.defaultPresetId, isNull);
    await store.setSelectedAsDefault();
    expect(store.defaultPresetId, 'a1');
    expect(await repo.getDefaultPresetId(), 'a1');
  });

  test('renameSelected persists the new name', () async {
    await _seedPreset(repo, 'a1', name: 'Alpha');
    final store = PresetStore(
      repository: repo,
      programType: ProgramType.programA,
    );
    await store.init();
    await store.selectPreset('a1');

    await store.renameSelected('Alpha Prime');
    final saved = await repo.getPreset('a1');
    expect(saved!.name, 'Alpha Prime');
    expect(store.presets.first.name, 'Alpha Prime');
  });

  test('filtering: Program-B preset is NOT in Program-A store', () async {
    await _seedPreset(repo, 'b1', name: 'Beta', program: ProgramType.programB);
    final store = PresetStore(
      repository: repo,
      programType: ProgramType.programA,
    );
    await store.init();
    expect(store.presets, isEmpty);

    // selectPreset against a cross-program id is a no-op.
    await store.selectPreset('b1');
    expect(store.selectedPresetId, isNull);
  });
}
