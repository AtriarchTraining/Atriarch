// lib/repositories/metrics_repository.dart
import 'package:sqflite/sqflite.dart';
import '../models/computed_metrics.dart';
import '../models/target_breakdown.dart';

/// Lightweight projection used exclusively by TrendAnalyticsScreen.
/// Only carries the four trended fields — avoids loading engagement rows.
class MetricSnapshot {
  final String sessionId;
  final int? drawMs;
  final int? avgReactionMs;
  final int? avgSplitMs;
  final int? avgTransitionMs;

  const MetricSnapshot({
    required this.sessionId,
    this.drawMs,
    this.avgReactionMs,
    this.avgSplitMs,
    this.avgTransitionMs,
  });

  factory MetricSnapshot._fromRow(Map<String, Object?> m) => MetricSnapshot(
        sessionId: m['session_id'] as String,
        drawMs: m['draw_ms'] as int?,
        avgReactionMs: m['avg_reaction_ms'] as int?,
        avgSplitMs: m['avg_split_ms'] as int?,
        avgTransitionMs: m['avg_transition_ms'] as int?,
      );
}

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

  /// Returns up to [limit] sessions ordered newest-first (rowid DESC).
  /// Only fetches the four trended columns — no engagement join needed.
  Future<List<MetricSnapshot>> listRecentMetrics({int limit = 20}) async {
    final rows = await _db.query(
      'session_metrics',
      columns: [
        'session_id',
        'draw_ms',
        'avg_reaction_ms',
        'avg_split_ms',
        'avg_transition_ms',
      ],
      orderBy: 'rowid DESC',
      limit: limit,
    );
    return rows.map(MetricSnapshot._fromRow).toList();
  }

  /// Cross-session GROUP BY aggregation over all target_engagements.
  /// Returns targets sorted slowest-first (highest avg reaction time).
  Future<List<TargetBreakdown>> aggregateByTarget() async {
    final rows = await _db.rawQuery('''
      SELECT
        target_id,
        AVG(reaction_ms)    AS avg_reaction_ms,
        SUM(hits_landed)    AS total_hits,
        SUM(required_hits)  AS total_required,
        SUM(was_no_shoot)   AS no_shoot_count,
        SUM(had_late_hit)   AS late_hit_count,
        COUNT(*)            AS total_engagements
      FROM target_engagements
      GROUP BY target_id
      ORDER BY avg_reaction_ms DESC
    ''');
    return rows.map(TargetBreakdown.fromMap).toList();
  }
}
