// lib/models/computed_metrics.dart
import 'package:flutter/foundation.dart';

@immutable
class TargetEngagementMetrics {
  final String sessionId;
  final int targetId;
  final int engagementIndex;
  final int activatedAtMs;
  final int precedingDelayMs;
  final int? reactionMs;
  final int hitsLanded;
  final int requiredHits;
  final int? engagementTimeMs;
  final bool wasNoShoot;
  final bool hadLateHit;

  const TargetEngagementMetrics({
    required this.sessionId,
    required this.targetId,
    required this.engagementIndex,
    required this.activatedAtMs,
    required this.precedingDelayMs,
    required this.hitsLanded,
    required this.requiredHits,
    this.reactionMs,
    this.engagementTimeMs,
    this.wasNoShoot = false,
    this.hadLateHit = false,
  });

  Map<String, Object?> toMap() => {
        'session_id': sessionId,
        'target_id': targetId,
        'engagement_index': engagementIndex,
        'activated_at': activatedAtMs,
        'preceding_delay_ms': precedingDelayMs,
        'reaction_ms': reactionMs,
        'hits_landed': hitsLanded,
        'required_hits': requiredHits,
        'engagement_time_ms': engagementTimeMs,
        'was_no_shoot': wasNoShoot ? 1 : 0,
        'had_late_hit': hadLateHit ? 1 : 0,
      };
}

@immutable
class ComputedMetrics {
  final String sessionId;
  final int? drawMs;
  final int? totalDurationMs;
  final int totalRoundsFired;
  final int noShootCount;
  final int lateHitCount;
  final int? avgReactionMs;
  final int? medianReactionMs;
  final int? stddevReactionMs;
  final int? avgSplitMs;
  final int? avgTransitionMs;
  final bool dataQualityWarning;
  final int metricsVersion;
  final List<TargetEngagementMetrics> engagements;

  const ComputedMetrics({
    required this.sessionId,
    required this.totalRoundsFired,
    required this.noShootCount,
    required this.lateHitCount,
    required this.metricsVersion,
    required this.engagements,
    this.drawMs,
    this.totalDurationMs,
    this.avgReactionMs,
    this.medianReactionMs,
    this.stddevReactionMs,
    this.avgSplitMs,
    this.avgTransitionMs,
    this.dataQualityWarning = false,
  });

  Map<String, Object?> toSessionMetricsMap() => {
        'session_id': sessionId,
        'draw_ms': drawMs,
        'total_duration_ms': totalDurationMs,
        'total_rounds_fired': totalRoundsFired,
        'no_shoot_count': noShootCount,
        'late_hit_count': lateHitCount,
        'avg_reaction_ms': avgReactionMs,
        'median_reaction_ms': medianReactionMs,
        'avg_split_ms': avgSplitMs,
        'avg_transition_ms': avgTransitionMs,
        'stddev_reaction_ms': stddevReactionMs,
        'data_quality_warning': dataQualityWarning ? 1 : 0,
        'metrics_version': metricsVersion,
      };
}
