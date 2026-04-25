// lib/services/metrics_engine.dart
import 'dart:math' as math;
import '../constants.dart';
import '../models/computed_metrics.dart';
import '../models/session_event.dart';

// Threshold for classifying a preceding delay as a "natural transition" vs a
// randomised drill delay. At or below this value the pair counts as a transition
// (last HIT prev → first HIT next). Above it the gap is drill-programmed dead
// time; the engagement is treated as an independent reaction, not a transition.
// 150ms chosen as a practical upper bound for a shooter's natural target-to-target
// movement time while still clearing firmware ACK latency (~50ms).
const int _kTransitionThresholdMs = 150;

class MetricsEngine {
  MetricsEngine._();

  static ComputedMetrics compute(String sessionId, List<SessionEvent> events) {
    // Per-targetId builder map supports Program B's concurrent multi-target
    // activations. Program A still works correctly: when a new ACT for a
    // target arrives while that same target has an open builder (which
    // shouldn't happen in practice but is safe), the old builder is closed
    // and a new one opened — same behaviour as before for Program A's
    // sequential single-target-at-a-time pattern.
    final activeBuilders = <int, _EngagementBuilder>{};
    final builders = <_EngagementBuilder>[];
    // Track the most recent DONE timestamp seen across all targets so that
    // precedingDelayMs is computed relative to the latest completion,
    // regardless of which target completed last.
    DateTime? lastDoneAt;
    int engagementIndex = 0;

    for (final event in events) {
      final tid = event.targetId ?? 0;
      switch (event.type) {
        case EventType.targetActivated:
          // Close any pre-existing builder for this targetId. This handles the
          // edge case where a target fires twice without a DONE between them
          // (e.g. firmware sends a second CMD_ACTIVATE before EVT_COMPLETE).
          final existing = activeBuilders.remove(tid);
          if (existing != null) builders.add(existing);
          final delayMs = lastDoneAt != null
              ? (event.timestamp.millisecondsSinceEpoch -
                      lastDoneAt.millisecondsSinceEpoch)
                  .clamp(0, 0x7FFFFFFF)
              : 0;
          activeBuilders[tid] = _EngagementBuilder(
            targetId: tid,
            engagementIndex: engagementIndex++,
            activatedAt: event.timestamp,
            precedingDelayMs: delayMs,
            requiredHits: event.requiredHits ?? 1,
          );
        case EventType.hitDetected:
          activeBuilders[tid]?.hitTimestamps.add(event.timestamp);
        case EventType.noShootViolation:
          if (activeBuilders[tid] != null) {
            activeBuilders[tid]!.wasNoShoot = true;
          }
        case EventType.lateHit:
          if (activeBuilders[tid] != null) {
            activeBuilders[tid]!.hadLateHit = true;
          }
        case EventType.targetComplete:
          final b = activeBuilders.remove(tid);
          if (b != null) {
            b.completedAt = event.timestamp;
            builders.add(b);
            // Update lastDoneAt to the most recent completion across all targets.
            if (lastDoneAt == null ||
                event.timestamp.isAfter(lastDoneAt)) {
              lastDoneAt = event.timestamp;
            }
          }
        case EventType.drillFinished:
          // Flush all remaining open builders (concurrent targets mid-engagement).
          for (final b in activeBuilders.values) {
            builders.add(b);
          }
          activeBuilders.clear();
        default:
          break;
      }
    }
    // Flush any builders still open after the event stream ends (no FIN event).
    for (final b in activeBuilders.values) {
      builders.add(b);
    }

    // Sort by engagementIndex so output order is deterministic and matches
    // the original activation-order guarantee from the single-pending design.
    builders.sort((a, b) => a.engagementIndex.compareTo(b.engagementIndex));

    final actEvents =
        events.where((e) => e.type == EventType.targetActivated).toList();
    final hitEvents =
        events.where((e) => e.type == EventType.hitDetected).toList();
    final finEvent =
        events.where((e) => e.type == EventType.drillFinished).firstOrNull;

    final firstAct = actEvents.firstOrNull;
    final firstHit = hitEvents.firstOrNull;

    final drawMs = (firstAct != null && firstHit != null)
        ? firstHit.timestamp.difference(firstAct.timestamp).inMilliseconds
        : null;

    final totalDurationMs = (firstAct != null && finEvent != null)
        ? finEvent.timestamp.difference(firstAct.timestamp).inMilliseconds
        : null;

    final reactions = builders
        .where((b) => b.hitTimestamps.isNotEmpty)
        .map((b) =>
            b.hitTimestamps.first.difference(b.activatedAt).inMilliseconds)
        .toList();

    final splits = <int>[];
    for (final b in builders) {
      for (int i = 1; i < b.hitTimestamps.length; i++) {
        splits.add(b.hitTimestamps[i]
            .difference(b.hitTimestamps[i - 1])
            .inMilliseconds);
      }
    }

    final transitions = <int>[];
    for (int i = 1; i < builders.length; i++) {
      final prev = builders[i - 1];
      final curr = builders[i];
      if (curr.precedingDelayMs <= _kTransitionThresholdMs &&
          prev.hitTimestamps.isNotEmpty &&
          curr.hitTimestamps.isNotEmpty) {
        transitions.add(curr.hitTimestamps.first
            .difference(prev.hitTimestamps.last)
            .inMilliseconds);
      }
    }

    final dataQualityWarning =
        builders.any((b) => b.hitTimestamps.isEmpty && b.completedAt == null);

    return ComputedMetrics(
      sessionId: sessionId,
      drawMs: drawMs,
      totalDurationMs: totalDurationMs,
      totalRoundsFired: hitEvents.length,
      noShootCount:
          events.where((e) => e.type == EventType.noShootViolation).length,
      lateHitCount: events.where((e) => e.type == EventType.lateHit).length,
      avgReactionMs: reactions.isNotEmpty ? _mean(reactions) : null,
      medianReactionMs: reactions.isNotEmpty ? _median(reactions) : null,
      stddevReactionMs: reactions.isNotEmpty ? _stddev(reactions) : null,
      avgSplitMs: splits.isNotEmpty ? _mean(splits) : null,
      avgTransitionMs: transitions.isNotEmpty ? _mean(transitions) : null,
      dataQualityWarning: dataQualityWarning,
      metricsVersion: kMetricsVersion,
      engagements: builders.map((b) => b.toMetrics(sessionId)).toList(),
    );
  }

  static int _mean(List<int> values) =>
      (values.reduce((a, b) => a + b) / values.length).round();

  static int _median(List<int> values) {
    final sorted = List<int>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : ((sorted[mid - 1] + sorted[mid]) / 2).round();
  }

  static int _stddev(List<int> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values
            .map((v) => (v - mean) * (v - mean))
            .reduce((a, b) => a + b) /
        values.length;
    return math.sqrt(variance).round();
  }
}

class _EngagementBuilder {
  final int targetId;
  final int engagementIndex;
  final DateTime activatedAt;
  final int precedingDelayMs;
  final int requiredHits;
  final List<DateTime> hitTimestamps = [];
  bool wasNoShoot = false;
  bool hadLateHit = false;
  DateTime? completedAt;

  _EngagementBuilder({
    required this.targetId,
    required this.engagementIndex,
    required this.activatedAt,
    required this.precedingDelayMs,
    required this.requiredHits,
  });

  TargetEngagementMetrics toMetrics(String sessionId) {
    final reactionMs = hitTimestamps.isNotEmpty
        ? hitTimestamps.first.difference(activatedAt).inMilliseconds
        : null;
    final engagementTimeMs = completedAt != null
        ? completedAt!.difference(activatedAt).inMilliseconds
        : null;
    return TargetEngagementMetrics(
      sessionId: sessionId,
      targetId: targetId,
      engagementIndex: engagementIndex,
      activatedAtMs: activatedAt.millisecondsSinceEpoch,
      precedingDelayMs: precedingDelayMs,
      reactionMs: reactionMs,
      hitsLanded: hitTimestamps.length,
      requiredHits: requiredHits,
      engagementTimeMs: engagementTimeMs,
      wasNoShoot: wasNoShoot,
      hadLateHit: hadLateHit,
    );
  }
}
