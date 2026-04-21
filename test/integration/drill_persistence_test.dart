import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/session_repository.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/state/shooter_state.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() => initializeTestDatabase());

  group('AppState persistence integration', () {
    late Database db;
    late ShooterRepository shooters;
    late SessionRepository sessions;
    late ShooterState shooterState;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await DatabaseHelper.openForTesting();
      shooters = ShooterRepository(db);
      sessions = SessionRepository(db);
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

    test('startDrill creates a session row under the current shooter', () async {
      final appState = AppState.forTesting(
        sessions: sessions,
        shooterState: shooterState,
      );
      final config = DrillConfig(programType: ProgramType.programA);
      await appState.startDrill(config);

      final rows = await db.query('sessions');
      expect(rows, hasLength(1));
      expect(rows.first['shooter_id'], 'j');
      expect(rows.first['program_type'], 'A');
      expect(rows.first['ended_at'], isNull);
    });

    test('events received during drill are persisted after flush', () async {
      final appState = AppState.forTesting(
        sessions: sessions,
        shooterState: shooterState,
      );
      await appState.startDrill(DrillConfig(programType: ProgramType.programA));

      appState.handleSessionEventForTesting(
        SessionEvent(type: EventType.targetActivated, targetId: 1),
      );
      appState.handleSessionEventForTesting(
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1),
      );
      await appState.forceFlushForTesting();

      final evts = await db.query('session_events');
      expect(evts, hasLength(2));
    });

    test('FIN event closes session with finished_normally=1', () async {
      final appState = AppState.forTesting(
        sessions: sessions,
        shooterState: shooterState,
      );
      await appState.startDrill(DrillConfig(programType: ProgramType.programA));
      appState.handleSessionEventForTesting(
        SessionEvent(type: EventType.drillFinished),
      );
      await appState.forceFlushForTesting();

      final rows = await db.query('sessions');
      expect(rows.first['ended_at'], isNotNull);
      expect(rows.first['finished_normally'], 1);
    });
  });
}
