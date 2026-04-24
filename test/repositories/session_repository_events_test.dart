import 'package:atriarch/constants.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/models/session_record.dart';
import 'package:atriarch/repositories/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SessionRepository.getEventsFor', () {
    test('returns events in sequence order', () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = SessionRepository(db);
      await repo.insert(SessionRecord(
        id: 's1',
        shooterId: kUnassignedShooterId,
        programType: 'A',
        configJson: '{}',
        configHash: 'hash',
        startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        finishedNormally: false,
        iterationsCompleted: 0,
      ));
      await repo.appendEvents('s1', [
        SessionEvent(
          type: EventType.targetActivated,
          targetId: 1,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1100),
        ),
        SessionEvent(
          type: EventType.hitDetected,
          targetId: 1,
          hitNumber: 1,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1200),
        ),
        SessionEvent(
          type: EventType.drillFinished,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1300),
        ),
      ]);

      final events = await repo.getEventsFor('s1');
      expect(events, hasLength(3));
      expect(events[0].type, EventType.targetActivated);
      expect(events[1].type, EventType.hitDetected);
      expect(events[2].type, EventType.drillFinished);
      await db.close();
    });

    test('returns empty list for unknown session id', () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = SessionRepository(db);
      expect(await repo.getEventsFor('nope'), isEmpty);
      await db.close();
    });
  });
}
