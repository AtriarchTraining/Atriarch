import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/constants.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import 'package:atriarch/state/shooter_state.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() => initializeTestDatabase());

  group('ShooterState', () {
    late Database db;
    late ShooterRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await DatabaseHelper.openForTesting();
      repo = ShooterRepository(db);
    });

    tearDown(() => db.close());

    test('initialize() with no saved id defaults to Unassigned', () async {
      final state = ShooterState(repo);
      await state.initialize();
      expect(state.current!.id, kUnassignedShooterId);
    });

    test('initialize() loads saved shooter id from preferences', () async {
      await repo.insert(Shooter(
        id: 'jeremy',
        displayName: 'Jeremy',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ));
      SharedPreferences.setMockInitialValues(
        {kPrefsLastShooterIdKey: 'jeremy'},
      );
      final state = ShooterState(repo);
      await state.initialize();
      expect(state.current!.id, 'jeremy');
    });

    test('selectShooter persists id and notifies listeners', () async {
      await repo.insert(Shooter(
        id: 'x',
        displayName: 'X',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ));
      final state = ShooterState(repo);
      await state.initialize();
      var notified = 0;
      state.addListener(() => notified++);

      await state.selectShooter('x');

      expect(state.current!.id, 'x');
      expect(notified, greaterThanOrEqualTo(1));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPrefsLastShooterIdKey), 'x');
    });

    test('selectShooter throws for unknown id', () async {
      final state = ShooterState(repo);
      await state.initialize();
      expect(
        () => state.selectShooter('ghost'),
        throwsA(isA<StateError>()),
      );
    });

    test('if saved id no longer exists, falls back to Unassigned', () async {
      SharedPreferences.setMockInitialValues(
        {kPrefsLastShooterIdKey: 'deleted-shooter'},
      );
      final state = ShooterState(repo);
      await state.initialize();
      expect(state.current!.id, kUnassignedShooterId);
    });
  });
}
