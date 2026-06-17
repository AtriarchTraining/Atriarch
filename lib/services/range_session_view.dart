import 'package:sqflite/sqflite.dart';

import '../models/session_record.dart';
import '../repositories/session_repository.dart';
import 'preferences_repository.dart';

/// Derived "current range session" view.
///
/// A range session = the drills the shooter has run during their current
/// range visit. Bounded by the 8h inactivity rule:
/// - If the last stamped activity was >=8h ago, the cutoff is "now"
///   (nothing visible — the previous visit's drills are stale).
/// - Otherwise the cutoff is [visit start], set on the first activity
///   following a >=8h gap (or cold-start). Drills started at or after
///   the visit start stay visible for the whole visit even as subsequent
///   activity heartbeats advance [PreferencesRepository.lastRangeActivity].
///
/// Two preference keys drive this:
/// - `last_range_activity_ms` — bumped on every [markActivity]; drives the
///   8h gap check.
/// - `range_visit_start_ms` — set only when a new visit begins; used as the
///   `sessions.started_at >= ?` cutoff.
///
/// No new storage table: [listCurrent] is a query against plan-1's
/// `sessions` table, and [clearCurrent] re-stamps both keys to now.
class RangeSessionView {
  static const Duration _gap = Duration(hours: 8);

  final SessionRepository sessions;
  final PreferencesRepository preferences;
  final DateTime Function() _clock;

  RangeSessionView({
    required this.sessions,
    required this.preferences,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The effective cutoff for the visible list. If no activity is stamped,
  /// or the gap since last activity exceeds [_gap], return now (nothing
  /// visible). Otherwise return the visit-start timestamp.
  Future<DateTime> currentCutoff() async {
    final last = await preferences.getLastRangeActivity();
    final now = _clock();
    if (last == null || now.difference(last) >= _gap) return now;
    final visitStart = await preferences.getVisitStart();
    return visitStart ?? last;
  }

  /// Sessions started at or after the current cutoff, most recent first.
  Future<List<SessionRecord>> listCurrent() async {
    final cutoff = await currentCutoff();
    final db = _dbFor(sessions);
    final rows = await db.query(
      'sessions',
      where: 'started_at >= ?',
      whereArgs: [cutoff.millisecondsSinceEpoch],
      orderBy: 'started_at DESC',
    );
    return rows.map(SessionRecord.fromMap).toList();
  }

  /// Stamp current time as "activity". Call on drill start AND end.
  /// On the first call following a >=8h gap (or a cold-start), also stamps
  /// the visit-start timestamp — which becomes the list cutoff for the rest
  /// of the visit. Subsequent calls within the visit only bump last-activity
  /// so the 8h keep-alive advances without hiding drills already started.
  Future<void> markActivity() async {
    final now = _clock();
    final last = await preferences.getLastRangeActivity();
    final visitStart = await preferences.getVisitStart();
    final isNewVisit =
        last == null || now.difference(last) >= _gap || visitStart == null;
    if (isNewVisit) {
      await preferences.setVisitStart(now);
    }
    await preferences.setLastRangeActivity(now);
  }

  /// "Clear this range session" → reset both keys to now. Nothing is
  /// deleted from the sessions table.
  Future<void> clearCurrent() async {
    final now = _clock();
    await preferences.setVisitStart(now);
    await preferences.setLastRangeActivity(now);
  }

  // SessionRepository exposes its Database internally; reach in because
  // the view needs a cross-table query (sessions ORDER BY started_at) that
  // the repository's current API doesn't expose as a single call.
  // If this proves awkward in the future, promote the query into
  // SessionRepository.listStartedSince(DateTime).
  Database _dbFor(SessionRepository repo) {
    // ignore: invalid_use_of_visible_for_testing_member
    return repo.rawDbForRangeView;
  }
}
