import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/session_event.dart';
import '../models/session_record.dart';

class SessionRepository {
  final Database _db;
  SessionRepository(this._db);

  /// Escape hatch for services that need cross-table queries (e.g.
  /// RangeSessionView). Do NOT use for CRUD that could live on a repository.
  @visibleForTesting
  Database get rawDbForRangeView => _db;

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

  /// Returns sessions ordered by started_at descending (newest first).
  Future<List<SessionRecord>> listSessions({int limit = 50}) async {
    final rows = await _db.query(
      'sessions',
      orderBy: 'started_at DESC',
      limit: limit,
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

  /// Returns every event for a session, ordered by sequence.
  Future<List<SessionEvent>> getEventsFor(String sessionId) async {
    final rows = await _db.query(
      'session_events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'sequence ASC',
    );
    return rows.map(_rowToEvent).toList();
  }

  static SessionEvent _rowToEvent(Map<String, Object?> row) => SessionEvent(
        type: _codeToType(row['type'] as String),
        targetId: row['target_id'] as int?,
        hitNumber: row['hit_number'] as int?,
        requiredHits: row['required_hits'] as int?,
        totalTimeMs: row['total_time_ms'] as int?,
        errorDetail: row['error_detail'] as String?,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
      );

  static EventType _codeToType(String code) {
    switch (code) {
      case 'ACT':
        return EventType.targetActivated;
      case 'HIT':
        return EventType.hitDetected;
      case 'DONE':
        return EventType.targetComplete;
      case 'NS':
        return EventType.noShootViolation;
      case 'LATE':
        return EventType.lateHit;
      case 'FIN':
        return EventType.drillFinished;
      case 'ERROR':
      case 'ERR':
      default:
        return EventType.error;
    }
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
