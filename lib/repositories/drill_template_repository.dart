import 'package:sqflite/sqflite.dart';

import '../models/drill_template.dart';

/// CRUD over the `drill_templates` SQLite table.
///
/// User-facing label is "preset"; the code-level name is DrillTemplate to
/// match the schema. App-wide templates have shooter_id NULL.
class DrillTemplateRepository {
  final Database _db;
  DrillTemplateRepository(this._db);

  Future<void> insert(DrillTemplate t) async {
    await _db.insert(
      'drill_templates',
      t.toRow(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Insert or replace — used by the "Save preset" flow which reuses an id
  /// on re-save.
  Future<void> upsert(DrillTemplate t) async {
    await _db.insert(
      'drill_templates',
      t.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DrillTemplate?> getById(String id) async {
    final rows = await _db.query(
      'drill_templates',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DrillTemplate.fromRow(rows.first);
  }

  /// All templates sorted alphabetically by name (case-insensitive). Matches
  /// gate-2's dropdown ordering.
  Future<List<DrillTemplate>> listAll() async {
    final rows = await _db.query(
      'drill_templates',
      orderBy: 'LOWER(name) ASC',
    );
    return rows.map(DrillTemplate.fromRow).toList();
  }

  Future<void> delete(String id) async {
    await _db.delete(
      'drill_templates',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
