import 'dart:io';

import 'package:atriarch/data/hive_bootstrap.dart';
import 'package:atriarch/data/session_repository.dart';
import 'package:atriarch/data/session_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('atriarch_session_');
    Hive.init(tempDir.path);
    registerAtriarchAdapters();
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  SessionSummary sample(String id, {DateTime? startedAt}) {
    return SessionSummary.create(
      drillId: id,
      presetName: 'Walk-back',
      startedAt: startedAt ?? DateTime.utc(2026, 4, 20, 9),
      duration: const Duration(minutes: 2, seconds: 30),
      completions: 5,
      violations: 0,
      lateHits: 1,
    );
  }

  test('init/close and beginSessionIfNeeded stamps start on fresh run',
      () async {
    DateTime now = DateTime.utc(2026, 4, 20, 10);
    final repo = SessionRepository(clock: () => now);
    await repo.init();

    expect(repo.isInitialized, isTrue);
    expect(repo.sessionStart, isNull);
    expect(repo.currentSessionDrills, isEmpty);

    await repo.beginSessionIfNeeded();
    expect(repo.sessionStart, now);

    await repo.close();
  });

  test('appendDrill caches in memory, persists, and emits on watch',
      () async {
    DateTime now = DateTime.utc(2026, 4, 20, 10);
    final repo = SessionRepository(clock: () => now);
    await repo.init();
    await repo.beginSessionIfNeeded();

    final events = <List<SessionSummary>>[];
    final sub = repo.watch().listen(events.add);

    await repo.appendDrill(sample('d1'));
    await repo.appendDrill(sample('d2'));

    expect(repo.currentSessionDrills.map((s) => s.drillId), ['d1', 'd2']);
    // Stream should have emitted twice (one per append).
    await Future<void>.delayed(Duration.zero);
    expect(events.length, 2);
    expect(events.last.map((s) => s.drillId), ['d1', 'd2']);

    await sub.cancel();
    await repo.close();
  });

  test('8h auto-clear: stale session wipes history and restamps', () async {
    DateTime now = DateTime.utc(2026, 4, 20, 10);
    var repo = SessionRepository(clock: () => now);
    await repo.init();
    await repo.beginSessionIfNeeded();
    await repo.appendDrill(sample('d1'));
    await repo.appendDrill(sample('d2'));
    expect(repo.currentSessionDrills, hasLength(2));
    final originalStart = repo.sessionStart;
    await repo.close();

    // Simulate app reopen 9h later — a new repo instance, stale session.
    now = DateTime.utc(2026, 4, 20, 19);
    repo = SessionRepository(clock: () => now);
    await repo.init();
    // Cache repopulates from disk before beginSessionIfNeeded runs.
    expect(repo.currentSessionDrills, hasLength(2));
    expect(repo.sessionStart, originalStart);

    await repo.beginSessionIfNeeded();

    expect(repo.currentSessionDrills, isEmpty);
    expect(repo.sessionStart, now);
    await repo.close();
  });

  test('under 8h: beginSessionIfNeeded preserves session', () async {
    DateTime now = DateTime.utc(2026, 4, 20, 10);
    var repo = SessionRepository(clock: () => now);
    await repo.init();
    await repo.beginSessionIfNeeded();
    await repo.appendDrill(sample('d1'));
    final start = repo.sessionStart;
    await repo.close();

    // Re-open 3h later.
    now = DateTime.utc(2026, 4, 20, 13);
    repo = SessionRepository(clock: () => now);
    await repo.init();
    await repo.beginSessionIfNeeded();

    expect(repo.currentSessionDrills, hasLength(1));
    expect(repo.sessionStart, start);
    await repo.close();
  });

  test('exactly 8h hits threshold and clears', () async {
    DateTime now = DateTime.utc(2026, 4, 20, 10);
    var repo = SessionRepository(clock: () => now);
    await repo.init();
    await repo.beginSessionIfNeeded();
    await repo.appendDrill(sample('d1'));
    await repo.close();

    now = DateTime.utc(2026, 4, 20, 18); // exactly +8h
    repo = SessionRepository(clock: () => now);
    await repo.init();
    await repo.beginSessionIfNeeded();

    expect(repo.currentSessionDrills, isEmpty);
    expect(repo.sessionStart, now);
    await repo.close();
  });

  test('clearSession wipes history without restamping', () async {
    DateTime now = DateTime.utc(2026, 4, 20, 10);
    final repo = SessionRepository(clock: () => now);
    await repo.init();
    await repo.beginSessionIfNeeded();
    await repo.appendDrill(sample('d1'));

    await repo.clearSession();
    expect(repo.currentSessionDrills, isEmpty);
    expect(repo.sessionStart, isNull);

    await repo.close();
  });

  test('methods throw before init()', () async {
    final fresh = SessionRepository();
    expect(fresh.beginSessionIfNeeded, throwsA(isA<StateError>()));
  });
}
