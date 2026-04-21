// lib/services/orphan_recovery.dart
//
// On app startup, any session row with ended_at IS NULL was left open by a
// crash / kill / disconnect. Close each one using the last event timestamp
// (or started_at if no events), and mark finished_normally=0.

import '../repositories/session_repository.dart';

class OrphanRecovery {
  /// Returns the number of sessions closed.
  static Future<int> sweep(SessionRepository sessions) async {
    final orphans = await sessions.findOrphanSessions();
    var closed = 0;
    for (final s in orphans) {
      final last = await sessions.lastEventTimestamp(s.id);
      await sessions.closeSession(
        id: s.id,
        endedAt: last ?? s.startedAt,
        finishedNormally: false,
        iterationsCompleted: s.iterationsCompleted,
      );
      closed++;
    }
    return closed;
  }
}
