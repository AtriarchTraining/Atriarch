import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/models/session_record.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/session_repository.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() => initializeTestDatabase());

  group('SessionRepository', () {
    late Database db;
    late SessionRepository sessions;
    late ShooterRepository shooters;

    setUp(() async {
      db = await DatabaseHelper.openForTesting();
      sessions = SessionRepository(db);
      shooters = ShooterRepository(db);
      await shooters.insert(Shooter(
        id: 'sh-1',
        displayName: 'Test',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ));
    });

    tearDown(() async {
      await db.close();
    });

    SessionRecord mkSession({String id = 's1', DateTime? startedAt}) =>
        SessionRecord(
          id: id,
          shooterId: 'sh-1',
          programType: 'A',
          configJson: '{}',
          configHash: 'hash',
          startedAt: startedAt ?? DateTime.fromMillisecondsSinceEpoch(1000),
          finishedNormally: false,
          iterationsCompleted: 0,
        );

    test('insert + getById round-trip', () async {
      await sessions.insert(mkSession());
      final back = await sessions.getById('s1');
      expect(back!.id, 's1');
      expect(back.finishedNormally, isFalse);
    });

    test('appendEvents persists in order with monotonic sequences', () async {
      await sessions.insert(mkSession());
      await sessions.appendEvents('s1', [
        SessionEvent(type: EventType.targetActivated, targetId: 1),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1),
      ]);
      final rows = await db.query(
        'session_events',
        where: 'session_id = ?',
        whereArgs: ['s1'],
        orderBy: 'sequence ASC',
      );
      expect(rows, hasLength(2));
      expect(rows[0]['sequence'], 0);
      expect(rows[1]['sequence'], 1);
      expect(rows[0]['type'], 'ACT');
      expect(rows[1]['type'], 'HIT');
    });

    test('appendEvents continues sequence after prior append', () async {
      await sessions.insert(mkSession());
      await sessions.appendEvents('s1', [
        SessionEvent(type: EventType.targetActivated, targetId: 1),
      ]);
      await sessions.appendEvents('s1', [
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1),
      ]);
      final rows = await db.query(
        'session_events',
        where: 'session_id = ?',
        whereArgs: ['s1'],
        orderBy: 'sequence ASC',
      );
      expect(rows.map((r) => r['sequence']), [0, 1]);
    });

    test('closeSession sets ended_at + finished_normally', () async {
      await sessions.insert(mkSession());
      await sessions.closeSession(
        id: 's1',
        endedAt: DateTime.fromMillisecondsSinceEpoch(5000),
        finishedNormally: true,
        iterationsCompleted: 5,
      );
      final back = (await sessions.getById('s1'))!;
      expect(back.endedAt, DateTime.fromMillisecondsSinceEpoch(5000));
      expect(back.finishedNormally, isTrue);
      expect(back.iterationsCompleted, 5);
    });

    test('findOrphanSessions returns sessions with ended_at NULL', () async {
      await sessions.insert(mkSession(id: 'open'));
      await sessions.insert(mkSession(id: 'closed'));
      await sessions.closeSession(
        id: 'closed',
        endedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        finishedNormally: true,
        iterationsCompleted: 1,
      );
      final orphans = await sessions.findOrphanSessions();
      expect(orphans.map((s) => s.id), ['open']);
    });

    test('deleting a shooter cascades to sessions and events', () async {
      await sessions.insert(mkSession());
      await sessions.appendEvents('s1', [
        SessionEvent(type: EventType.targetActivated, targetId: 1),
      ]);
      await shooters.delete('sh-1');
      expect(await sessions.getById('s1'), isNull);
      final evts = await db.query('session_events', where: 'session_id = ?', whereArgs: ['s1']);
      expect(evts, isEmpty);
    });
  });
}
