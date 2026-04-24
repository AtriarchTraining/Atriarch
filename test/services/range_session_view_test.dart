import 'package:atriarch/constants.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/session_record.dart';
import 'package:atriarch/repositories/session_repository.dart';
import 'package:atriarch/services/preferences_repository.dart';
import 'package:atriarch/services/range_session_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

SessionRecord _rec(String id, int startedMs,
        {int? endedMs, bool finished = true}) =>
    SessionRecord(
      id: id,
      shooterId: kUnassignedShooterId,
      programType: 'A',
      configJson: '{}',
      configHash: 'h',
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedMs),
      endedAt:
          endedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(endedMs),
      finishedNormally: finished,
      iterationsCompleted: 0,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RangeSessionView', () {
    test('returns empty list when no sessions exist', () async {
      final db = await DatabaseHelper.openForTesting();
      final prefs = await SharedPreferences.getInstance();
      final view = RangeSessionView(
        sessions: SessionRepository(db),
        preferences: PreferencesRepository(prefs),
        clock: () => DateTime.fromMillisecondsSinceEpoch(1000000),
      );
      expect(await view.listCurrent(), isEmpty);
      await db.close();
    });

    test('returns all sessions since the cutoff when gap < 8h', () async {
      final db = await DatabaseHelper.openForTesting();
      final sessions = SessionRepository(db);
      final prefs = await SharedPreferences.getInstance();
      final preferences = PreferencesRepository(prefs);

      // Stamp last activity 2h ago (the view cutoff).
      final now = DateTime.fromMillisecondsSinceEpoch(1000000000000);
      final twoHoursAgo = now.subtract(const Duration(hours: 2));
      await preferences.setLastRangeActivity(twoHoursAgo);

      await sessions.insert(_rec('s1', twoHoursAgo.millisecondsSinceEpoch + 1));
      await sessions.insert(_rec('s2', now.millisecondsSinceEpoch - 60000));
      await sessions.insert(_rec(
        'old',
        twoHoursAgo.millisecondsSinceEpoch - 1,
      ));

      final view = RangeSessionView(
        sessions: sessions,
        preferences: preferences,
        clock: () => now,
      );
      final got = await view.listCurrent();
      expect(got.map((s) => s.id).toList(), ['s2', 's1']);
      await db.close();
    });

    test('resets cutoff to now when last activity was >= 8h ago', () async {
      final db = await DatabaseHelper.openForTesting();
      final sessions = SessionRepository(db);
      final prefs = await SharedPreferences.getInstance();
      final preferences = PreferencesRepository(prefs);

      final now = DateTime.fromMillisecondsSinceEpoch(1000000000000);
      final nineHoursAgo = now.subtract(const Duration(hours: 9));
      await preferences.setLastRangeActivity(nineHoursAgo);

      await sessions.insert(_rec('old', nineHoursAgo.millisecondsSinceEpoch + 1));

      final view = RangeSessionView(
        sessions: sessions,
        preferences: preferences,
        clock: () => now,
      );
      expect(await view.listCurrent(), isEmpty);
      await db.close();
    });

    test('markActivity stamps now and is read back by listCurrent', () async {
      final db = await DatabaseHelper.openForTesting();
      final sessions = SessionRepository(db);
      final prefs = await SharedPreferences.getInstance();
      final preferences = PreferencesRepository(prefs);

      final now = DateTime.fromMillisecondsSinceEpoch(1000000000000);
      final view = RangeSessionView(
        sessions: sessions,
        preferences: preferences,
        clock: () => now,
      );
      await view.markActivity();
      expect(await preferences.getLastRangeActivity(), now);
      await db.close();
    });

    test('clearCurrent sets cutoff to now without deleting rows', () async {
      final db = await DatabaseHelper.openForTesting();
      final sessions = SessionRepository(db);
      final prefs = await SharedPreferences.getInstance();
      final preferences = PreferencesRepository(prefs);

      final now = DateTime.fromMillisecondsSinceEpoch(1000000000000);
      final halfHourAgo = now.subtract(const Duration(minutes: 30));
      await preferences.setLastRangeActivity(halfHourAgo);
      await sessions.insert(_rec('s1', halfHourAgo.millisecondsSinceEpoch + 1));

      final view = RangeSessionView(
        sessions: sessions,
        preferences: preferences,
        clock: () => now,
      );
      // Before clear: session is visible.
      expect((await view.listCurrent()).map((s) => s.id), ['s1']);

      await view.clearCurrent();
      // After clear: visible list is empty; row still exists.
      expect(await view.listCurrent(), isEmpty);
      expect(await sessions.getById('s1'), isNotNull);
      await db.close();
    });
  });
}
