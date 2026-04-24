import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/session_repository.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import 'package:atriarch/services/preferences_repository.dart';
import 'package:atriarch/services/range_session_view.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/state/shooter_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() => initializeTestDatabase());

  group('range-session drill flow end-to-end', () {
    late Database db;
    late ShooterRepository shooters;
    late SessionRepository sessions;
    late PreferencesRepository preferences;
    late RangeSessionView rangeView;
    late ShooterState shooterState;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await DatabaseHelper.openForTesting();
      shooters = ShooterRepository(db);
      sessions = SessionRepository(db);
      final sp = await SharedPreferences.getInstance();
      preferences = PreferencesRepository(sp);
      rangeView = RangeSessionView(
        sessions: sessions,
        preferences: preferences,
      );
      await shooters.insert(Shooter(
        id: 'j',
        displayName: 'Jeremy',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ));
      shooterState = ShooterState(shooters);
      await shooterState.initialize();
      await shooterState.selectShooter('j');
    });

    tearDown(() => db.close());

    test('drill lifecycle: start → event batch → FIN persisted → listed',
        () async {
      // Cold-start: range-session view is empty.
      expect(await rangeView.listCurrent(), isEmpty);

      final appState = AppState.forTesting(
        sessions: sessions,
        shooterState: shooterState,
        preferences: preferences,
        rangeSessionView: rangeView,
      );

      // 1. Start a drill — startDrill stamps range activity + inserts row.
      final config = DrillConfig(programType: ProgramType.programA);
      await appState.startDrill(config);

      // 2. Simulate telemetry: ACT → HIT → FIN.
      appState.handleSessionEventForTesting(
        SessionEvent(
          type: EventType.targetActivated,
          targetId: 1,
          timestamp: DateTime.fromMillisecondsSinceEpoch(100),
        ),
      );
      appState.handleSessionEventForTesting(
        SessionEvent(
          type: EventType.hitDetected,
          targetId: 1,
          hitNumber: 1,
          timestamp: DateTime.fromMillisecondsSinceEpoch(200),
        ),
      );
      appState.handleSessionEventForTesting(
        SessionEvent(
          type: EventType.drillFinished,
          timestamp: DateTime.fromMillisecondsSinceEpoch(300),
        ),
      );
      await appState.forceFlushForTesting();

      // 3. RangeSessionView lists the finished drill.
      final listed = await rangeView.listCurrent();
      expect(listed, hasLength(1));
      expect(listed.first.shooterId, 'j');
      expect(listed.first.programType, 'A');
      expect(listed.first.finishedNormally, isTrue);

      // 4. getEventsFor returns the event stream we fed in (sequence order).
      final events =
          await sessions.getEventsFor(listed.first.id);
      expect(events.map((e) => e.type).toList(), [
        EventType.targetActivated,
        EventType.hitDetected,
        EventType.drillFinished,
      ]);

      // 5. last_range_activity_ms was stamped on drill start AND end.
      final activity = await preferences.getLastRangeActivity();
      expect(activity, isNotNull);
    });

    test('8h gap clears visible range session without deleting rows',
        () async {
      final longAgo = DateTime.now().subtract(const Duration(hours: 9));
      await preferences.setLastRangeActivity(longAgo);

      // Seed a session from the previous range visit.
      final appState = AppState.forTesting(
        sessions: sessions,
        shooterState: shooterState,
        preferences: preferences,
        rangeSessionView: rangeView,
      );
      // Directly insert a historical session (bypasses AppState clock so
      // we can place it in the past without freezing time).
      await db.insert('sessions', {
        'id': 'historical',
        'shooter_id': 'j',
        'program_type': 'A',
        'config_json': '{}',
        'config_hash': 'h',
        'started_at': longAgo.millisecondsSinceEpoch + 1,
        'ended_at': longAgo.millisecondsSinceEpoch + 100,
        'finished_normally': 1,
        'iterations_completed': 0,
      });

      // Without the 8h reset rule, listCurrent would return the historical
      // row. With it, the view is empty AND the row is still in the DB.
      expect(await rangeView.listCurrent(), isEmpty);
      final all = await db.query('sessions');
      expect(all, hasLength(1));

      // Unused outside asserts — silence analyzer.
      expect(appState.phase, isNotNull);
    });
  });
}
