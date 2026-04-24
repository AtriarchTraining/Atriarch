import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/models/session_record.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/session_repository.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import 'package:atriarch/services/orphan_recovery.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() => initializeTestDatabase());

  group('OrphanRecovery.sweep', () {
    late Database db;
    late SessionRepository sessions;

    setUp(() async {
      db = await DatabaseHelper.openForTesting();
      sessions = SessionRepository(db);
      await ShooterRepository(db).insert(Shooter(
        id: 'sh',
        displayName: 'X',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ));
    });

    tearDown(() => db.close());

    test('closes orphan with ended_at = last event timestamp', () async {
      await sessions.insert(SessionRecord(
        id: 'orphan',
        shooterId: 'sh',
        programType: 'A',
        configJson: '{}',
        configHash: 'h',
        startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        finishedNormally: false,
        iterationsCompleted: 0,
      ));
      await sessions.appendEvents('orphan', [
        SessionEvent(type: EventType.targetActivated, targetId: 1),
      ]);
      // Force the event timestamp by direct SQL (SessionEvent uses now()).
      await db.update(
        'session_events',
        {'timestamp': 2500},
        where: 'session_id = ?',
        whereArgs: ['orphan'],
      );

      final count = await OrphanRecovery.sweep(sessions);

      expect(count, 1);
      final back = (await sessions.getById('orphan'))!;
      expect(back.endedAt, DateTime.fromMillisecondsSinceEpoch(2500));
      expect(back.finishedNormally, isFalse);
    });

    test('closes orphan with no events using started_at as ended_at', () async {
      await sessions.insert(SessionRecord(
        id: 'empty',
        shooterId: 'sh',
        programType: 'A',
        configJson: '{}',
        configHash: 'h',
        startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        finishedNormally: false,
        iterationsCompleted: 0,
      ));

      await OrphanRecovery.sweep(sessions);

      final back = (await sessions.getById('empty'))!;
      expect(back.endedAt, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(back.finishedNormally, isFalse);
    });

    test('ignores already-closed sessions', () async {
      await sessions.insert(SessionRecord(
        id: 'closed',
        shooterId: 'sh',
        programType: 'A',
        configJson: '{}',
        configHash: 'h',
        startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        endedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        finishedNormally: true,
        iterationsCompleted: 3,
      ));
      final count = await OrphanRecovery.sweep(sessions);
      expect(count, 0);
      final back = (await sessions.getById('closed'))!;
      expect(back.finishedNormally, isTrue);
    });
  });
}
