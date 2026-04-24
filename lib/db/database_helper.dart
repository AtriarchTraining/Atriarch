// lib/db/database_helper.dart
//
// sqflite wrapper: singleton for the app, test-friendly via openForTesting().

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi;

import '../constants.dart';
import 'schema.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static Database? _instance;

  /// Returns the singleton DB, opening on first call. Production app path.
  static Future<Database> instance() async {
    final existing = _instance;
    if (existing != null) return existing;
    final docsDir = await getApplicationDocumentsDirectory();
    final path = p.join(docsDir.path, kDatabaseFileName);
    final db = await openDatabase(
      path,
      version: kDatabaseVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
    );
    _instance = db;
    return db;
  }

  /// Opens a fresh in-memory DB for tests. Does NOT populate `_instance`.
  /// Caller owns close().
  static Future<Database> openForTesting() async {
    return databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: kDatabaseVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
      ),
    );
  }

  /// Resets the singleton. Tests only.
  @visibleForTesting
  static Future<void> resetForTesting() async {
    await _instance?.close();
    _instance = null;
  }

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    for (final stmt in kSchemaV1Ddl) {
      batch.execute(stmt);
    }
    batch.rawInsert(
      kSeedUnassignedShooterSql,
      [
        kUnassignedShooterId,
        kUnassignedShooterName,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    await batch.commit(noResult: true);
  }
}
