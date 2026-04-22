import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/constants.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() {
    initializeTestDatabase();
  });

  group('DatabaseHelper schema v1', () {
    late Database db;

    setUp(() async {
      db = await DatabaseHelper.openForTesting();
    });

    tearDown(() async {
      await db.close();
    });

    test('all six tables exist', () async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
      );
      final names = tables.map((r) => r['name'] as String).toSet();
      expect(names, containsAll({
        'shooters',
        'drill_templates',
        'sessions',
        'session_events',
        'session_metrics',
        'target_engagements',
      }));
    });

    test('expected indexes exist', () async {
      final idx = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'",
      );
      final names = idx.map((r) => r['name'] as String).toSet();
      expect(names, containsAll({
        'idx_sessions_shooter_started',
        'idx_session_events_session_seq',
        'idx_target_engagements_session',
        'idx_target_engagements_session_target',
      }));
    });

    test('Unassigned shooter is seeded', () async {
      final rows = await db.query(
        'shooters',
        where: 'id = ?',
        whereArgs: [kUnassignedShooterId],
      );
      expect(rows, hasLength(1));
      expect(rows.first['display_name'], kUnassignedShooterName);
    });

    test('foreign keys are enforced', () async {
      // Attempting to insert a session with a non-existent shooter_id fails.
      expect(
        () => db.insert('sessions', {
          'id': 'test-session',
          'shooter_id': 'nonexistent',
          'program_type': 'A',
          'config_json': '{}',
          'config_hash': 'abc',
          'started_at': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
