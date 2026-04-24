// lib/repositories/metrics_repository.dart
import 'package:sqflite/sqflite.dart';
import '../models/computed_metrics.dart';

class MetricsRepository {
  final Database _db;
  MetricsRepository(this._db);

  Future<void> save(ComputedMetrics metrics) async {
    await _db.transaction((txn) async {
      await txn.insert(
        'session_metrics',
        metrics.toSessionMetricsMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'target_engagements',
        where: 'session_id = ?',
        whereArgs: [metrics.sessionId],
      );
      final batch = txn.batch();
      for (final eng in metrics.engagements) {
        batch.insert('target_engagements', eng.toMap());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<ComputedMetrics?> getForSession(String sessionId) async {
    final rows = await _db.query(
      'session_metrics',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final engRows = await _db.query(
      'target_engagements',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'engagement_index ASC',
    );

    return ComputedMetrics.fromSessionMetricsMap(
      rows.first,
      engagements: engRows
          .map(TargetEngagementMetrics.fromMap)
          .toList(),
    );
  }
}
