// Tests for FakeMetricsRepository in-memory stub.

import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/models/computed_metrics.dart';
import 'fake_metrics_repository.dart';

ComputedMetrics _makeMetrics(String sessionId) => ComputedMetrics(
      sessionId: sessionId,
      totalRoundsFired: 10,
      noShootCount: 0,
      lateHitCount: 1,
      metricsVersion: 1,
      engagements: const [],
      drawMs: 320,
      avgReactionMs: 450,
    );

void main() {
  group('FakeMetricsRepository', () {
    test('getForSession returns null for unknown sessionId', () async {
      final repo = FakeMetricsRepository();
      final result = await repo.getForSession('nonexistent-id');
      expect(result, isNull);
    });

    test('save then getForSession round-trips correctly', () async {
      final repo = FakeMetricsRepository();
      final metrics = _makeMetrics('session-abc');

      await repo.save(metrics);
      final retrieved = await repo.getForSession('session-abc');

      expect(retrieved, isNotNull);
      expect(retrieved!.sessionId, 'session-abc');
      expect(retrieved.totalRoundsFired, 10);
      expect(retrieved.drawMs, 320);
      expect(retrieved.avgReactionMs, 450);
      expect(retrieved.lateHitCount, 1);
    });

    test('save overwrites existing entry for same sessionId', () async {
      final repo = FakeMetricsRepository();
      final first = _makeMetrics('session-xyz');
      final second = ComputedMetrics(
        sessionId: 'session-xyz',
        totalRoundsFired: 20,
        noShootCount: 2,
        lateHitCount: 0,
        metricsVersion: 1,
        engagements: const [],
      );

      await repo.save(first);
      await repo.save(second);

      final retrieved = await repo.getForSession('session-xyz');
      expect(retrieved!.totalRoundsFired, 20);
      expect(retrieved.noShootCount, 2);
    });

    test('pre-seeded data is accessible via getForSession', () async {
      final seeded = _makeMetrics('seeded-session');
      final repo = FakeMetricsRepository(seed: {'seeded-session': seeded});

      final retrieved = await repo.getForSession('seeded-session');
      expect(retrieved, isNotNull);
      expect(retrieved!.sessionId, 'seeded-session');
      expect(retrieved.totalRoundsFired, 10);
    });

    test('pre-seeded data does not mutate original map', () async {
      final original = <String, ComputedMetrics>{};
      final repo = FakeMetricsRepository(seed: original);
      await repo.save(_makeMetrics('new-session'));

      // Original seed map should not be mutated
      expect(original, isEmpty);
    });
  });
}
