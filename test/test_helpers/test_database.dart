// test/test_helpers/test_database.dart
//
// Initializes sqflite to use the FFI backend (host-side, no device required)
// and hands back a fresh in-memory Database for each test.

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Call once per test run (idempotent) to install the FFI factory.
void initializeTestDatabase() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// Returns a fresh in-memory DB with schema v1 applied.
Future<Database> openTestDatabase({int version = 1}) async {
  initializeTestDatabase();
  return databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, v) async {
        // Note: this default helper is overridden in database_helper_test.dart
        // by using DatabaseHelper.openForTesting(). Other suites that need a
        // schema'd DB should use that instead.
      },
    ),
  );
}
