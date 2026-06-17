// In-memory fake MetricsRepository for widget tests.
// Real sqflite + widget tests deadlock on macOS — avoid DatabaseHelper here.
// Used by any widget test that mounts a screen depending on ComputedMetrics.

import 'package:atriarch/models/computed_metrics.dart';
import 'package:atriarch/models/target_breakdown.dart';
import 'package:atriarch/repositories/metrics_repository.dart';

class FakeMetricsRepository implements MetricsRepository {
  final Map<String, ComputedMetrics> _store;
  final List<TargetBreakdown> _breakdowns;

  FakeMetricsRepository({
    Map<String, ComputedMetrics>? seed,
    List<TargetBreakdown>? breakdowns,
  })  : _store = seed != null ? Map.of(seed) : {},
        _breakdowns = breakdowns != null ? List.of(breakdowns) : [];

  @override
  Future<void> save(ComputedMetrics metrics) async {
    _store[metrics.sessionId] = metrics;
  }

  @override
  Future<ComputedMetrics?> getForSession(String sessionId) async {
    return _store[sessionId];
  }

  @override
  Future<List<TargetBreakdown>> aggregateByTarget() async {
    return List.unmodifiable(_breakdowns);
  }

  @override
  Future<List<MetricSnapshot>> listRecentMetrics({int limit = 20}) async {
    return const [];
  }
}
