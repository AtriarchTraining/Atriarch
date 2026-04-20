import 'dart:io';

import 'package:atriarch/data/drill_log_repository.dart';
import 'package:atriarch/data/hive_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late Directory fakeDocsDir;
  late DrillLogRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('atriarch_drilllog_');
    fakeDocsDir = await Directory.systemTemp.createTemp('atriarch_docs_');
    Hive.init(tempDir.path);
    registerAtriarchAdapters();
    repo = DrillLogRepository(
      documentsDirProvider: () async => fakeDocsDir,
    );
    await repo.init();
  });

  tearDown(() async {
    await repo.close();
    await Hive.close();
    for (final d in [tempDir, fakeDocsDir]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  test('init/close reports state', () async {
    expect(repo.isInitialized, isTrue);
    await repo.close();
    expect(repo.isInitialized, isFalse);
    await repo.init();
    expect(repo.isInitialized, isTrue);
  });

  test('write/read/list/delete round-trip', () async {
    expect(await repo.listDrillIds(), isEmpty);
    expect(await repo.readLog('missing'), isNull);

    const payloadA = '{"version":1,"drillId":"a","events":[]}';
    const payloadB = '{"version":1,"drillId":"b","events":[]}';

    await repo.writeLog('a', payloadA);
    await repo.writeLog('b', payloadB);

    expect((await repo.listDrillIds()).toSet(), {'a', 'b'});
    expect(await repo.readLog('a'), payloadA);
    expect(await repo.readLog('b'), payloadB);

    // Overwrite semantics.
    const payloadA2 = '{"version":1,"drillId":"a","events":[{"t":1}]}';
    await repo.writeLog('a', payloadA2);
    expect(await repo.readLog('a'), payloadA2);

    await repo.deleteLog('a');
    expect(await repo.readLog('a'), isNull);
    expect((await repo.listDrillIds()).toSet(), {'b'});
  });

  test('exportLogToFile writes to <docs>/drill_logs/{drillId}.json', () async {
    const payload = '{"version":1,"drillId":"run-42","events":[]}';
    await repo.writeLog('run-42', payload);

    final path = await repo.exportLogToFile('run-42');

    final expectedPath =
        '${fakeDocsDir.path}/${DrillLogRepository.exportSubdir}/run-42.json';
    expect(path, expectedPath);

    final file = File(path);
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), payload);
  });

  test('exportLogToFile throws StateError when log missing', () async {
    expect(
      () => repo.exportLogToFile('never-written'),
      throwsA(isA<StateError>()),
    );
  });

  test('export creates the drill_logs subdirectory if missing', () async {
    // Sanity: subdir does not exist yet on a fresh fake docs dir.
    final subdir = Directory(
      '${fakeDocsDir.path}/${DrillLogRepository.exportSubdir}',
    );
    expect(await subdir.exists(), isFalse);

    await repo.writeLog('first', '{"version":1}');
    await repo.exportLogToFile('first');

    expect(await subdir.exists(), isTrue);
  });

  test('methods throw before init()', () async {
    final fresh = DrillLogRepository();
    expect(() => fresh.writeLog('x', '{}'), throwsA(isA<StateError>()));
  });
}
