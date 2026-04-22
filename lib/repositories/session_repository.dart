import 'package:sqflite/sqflite.dart';

import '../models/session_event.dart';
import '../models/session_record.dart';

class SessionRepository {
  final Database _db;
  SessionRepository(this._db);

  Future<void> insert(SessionRecord r) async {
    await _db.insert(
      'sessions',
      r.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<SessionRecord?> getById(String id) async {
    final rows = await _db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SessionRecord.fromMap(rows.first);
  }

  /// Append a batch of events to a session. Sequence numbers are assigned
  /// contiguously starting from (max existing sequence + 1), or 0 if empty.
  Future<void> appendEvents(String sessionId, List<SessionEvent> events) async {
    if (events.isEmpty) return;
    await _db.transaction((txn) async {
      final result = await txn.rawQuery(
        'SELECT COALESCE(MAX(sequence), -1) AS max_seq FROM session_events WHERE session_id = ?',
        [sessionId],
      );
      var nextSeq = (result.first['max_seq'] as int) + 1;
      final batch = txn.batch();
      for (final e in events) {
        batch.insert('session_events', {
          'session_id': sessionId,
          'sequence': nextSeq++,
          'type': _typeToCode(e.type),
          'target_id': e.targetId,
          'hit_number': e.hitNumber,
          'required_hits': e.requiredHits,
          'total_time_ms': e.totalTimeMs,
          'error_detail': e.errorDetail,
          'timestamp': e.timestamp.millisecondsSinceEpoch,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> closeSession({
    required String id,
    required DateTime endedAt,
    required bool finishedNormally,
    required int iterationsCompleted,
  }) async {
    await _db.update(
      'sessions',
      {
        'ended_at': endedAt.millisecondsSinceEpoch,
        'finished_normally': finishedNormally ? 1 : 0,
        'iterations_completed': iterationsCompleted,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<SessionRecord>> findOrphanSessions() async {
    final rows = await _db.query(
      'sessions',
      where: 'ended_at IS NULL',
    );
    return rows.map(SessionRecord.fromMap).toList();
  }

  /// Returns the timestamp of the last event in a session, or null if none.
  Future<DateTime?> lastEventTimestamp(String sessionId) async {
    final rows = await _db.rawQuery(
      'SELECT MAX(timestamp) AS ts FROM session_events WHERE session_id = ?',
      [sessionId],
    );
    final ts = rows.first['ts'];
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts as int);
  }

  static String _typeToCode(EventType t) {
    switch (t) {
      case EventType.targetActivated:
        return 'ACT';
      case EventType.hitDetected:
        return 'HIT';
      case EventType.targetComplete:
        return 'DONE';
      case EventType.noShootViolation:
        return 'NS';
      case EventType.lateHit:
        return 'LATE';
      case EventType.drillFinished:
        return 'FIN';
      case EventType.error:
        return 'ERROR';
    }
  }
}
