import 'package:sqflite/sqflite.dart';

import '../models/session_record.dart';
import '../repositories/session_repository.dart';
import 'preferences_repository.dart';

/// Derived "current range session" view.
///
/// A range session = the drills the shooter has run during their current
/// range visit. Bounded by the 8h inactivity rule: if the last stamped
/// activity was >=8h ago, the cutoff is "now" (nothing visible).
/// Otherwise the cutoff is the last-activity timestamp.
///
/// No new storage: [listCurrent] is a query against plan-1's `sessions`
/// table, and [clearCurrent] just re-stamps the cutoff.
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

  /// The effective cutoff for the visible list. If no last-activity stamp
  /// exists or the gap exceeds [_gap], the cutoff is now.
  Future<DateTime> currentCutoff() async {
    final last = await preferences.getLastRangeActivity();
    final now = _clock();
    if (last == null) return now;
    if (now.difference(last) >= _gap) return now;
    return last;
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
  Future<void> markActivity() async =>
      preferences.setLastRangeActivity(_clock());

  /// "Clear this range session" → set the cutoff to now. Nothing is deleted.
  Future<void> clearCurrent() async =>
      preferences.setLastRangeActivity(_clock());

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
