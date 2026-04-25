// In-memory fake MetricsRepository for widget tests.
// Real sqflite + widget tests deadlock on macOS — avoid DatabaseHelper here.
// Used by any widget test that mounts a screen depending on ComputedMetrics.

import 'package:atriarch/models/computed_metrics.dart';
import 'package:atriarch/repositories/metrics_repository.dart';

class FakeMetricsRepository implements MetricsRepository {
  final Map<String, ComputedMetrics> _store;

  FakeMetricsRepository({Map<String, ComputedMetrics>? seed})
      : _store = seed != null ? Map.of(seed) : {};

  @override
  Future<void> save(ComputedMetrics metrics) async {
    _store[metrics.sessionId] = metrics;
  }

  @override
  Future<ComputedMetrics?> getForSession(String sessionId) async {
    return _store[sessionId];
  }
}
