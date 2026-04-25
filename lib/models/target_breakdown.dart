// lib/models/target_breakdown.dart
import 'package:flutter/foundation.dart';

@immutable
class TargetBreakdown {
  final int targetId;
  final int avgReactionMs;
  final int totalHits;
  final int totalRequired;
  final int noShootCount;
  final int lateHitCount;
  final int totalEngagements;

  const TargetBreakdown({
    required this.targetId,
    required this.avgReactionMs,
    required this.totalHits,
    required this.totalRequired,
    required this.noShootCount,
    required this.lateHitCount,
    required this.totalEngagements,
  });

  double get hitRate =>
      totalRequired == 0 ? 0.0 : totalHits / totalRequired;

  bool get hasViolations => noShootCount > 0;

  factory TargetBreakdown.fromMap(Map<String, Object?> m) {
    final rawAvg = m['avg_reaction_ms'];
    final avgMs = rawAvg is double ? rawAvg.round() : (rawAvg as int? ?? 0);
    return TargetBreakdown(
      targetId: m['target_id'] as int,
      avgReactionMs: avgMs,
      totalHits: (m['total_hits'] as int?) ?? 0,
      totalRequired: (m['total_required'] as int?) ?? 0,
      noShootCount: (m['no_shoot_count'] as int?) ?? 0,
      lateHitCount: (m['late_hit_count'] as int?) ?? 0,
      totalEngagements: (m['total_engagements'] as int?) ?? 0,
    );
  }
}
