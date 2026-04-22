import 'package:sqflite/sqflite.dart';

import '../constants.dart';
import '../models/shooter.dart';

class ShooterRepository {
  final Database _db;
  ShooterRepository(this._db);

  Future<void> insert(Shooter s) async {
    await _db.insert(
      'shooters',
      s.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<Shooter?> getById(String id) async {
    final rows = await _db.query(
      'shooters',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Shooter.fromMap(rows.first);
  }

  Future<List<Shooter>> listAll() async {
    final rows = await _db.query(
      'shooters',
      orderBy: 'created_at DESC',
    );
    return rows.map(Shooter.fromMap).toList();
  }

  Future<void> update(Shooter s) async {
    await _db.update(
      'shooters',
      s.toMap(),
      where: 'id = ?',
      whereArgs: [s.id],
    );
  }

  Future<void> delete(String id) async {
    if (id == kUnassignedShooterId) {
      throw StateError('Cannot delete reserved Unassigned shooter');
    }
    await _db.delete(
      'shooters',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
