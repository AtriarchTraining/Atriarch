// test/services/metrics_engine_test.dart
import 'package:atriarch/constants.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/services/metrics_engine.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _t(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

void main() {
  const sid = 'session-1';

  group('MetricsEngine.compute — empty / trivial', () {
    test('empty event list returns zero counts and null timing', () {
      final m = MetricsEngine.compute(sid, []);
      expect(m.sessionId, sid);
      expect(m.totalRoundsFired, 0);
      expect(m.noShootCount, 0);
      expect(m.lateHitCount, 0);
      expect(m.drawMs, isNull);
      expect(m.avgReactionMs, isNull);
      expect(m.engagements, isEmpty);
      expect(m.metricsVersion, kMetricsVersion);
    });

    test('ACT with no HIT — reaction is null, engagement recorded', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(1000)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(5000)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.engagements, hasLength(1));
      expect(m.engagements.first.reactionMs, isNull);
      expect(m.drawMs, isNull);
      expect(m.totalRoundsFired, 0);
    });
  });

  group('MetricsEngine.compute — draw and reaction', () {
    test('draw_ms = first ACT to first HIT', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(1000)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(1350)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 350, timestamp: _t(1350)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(2000)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.drawMs, 350);
      expect(m.engagements.first.reactionMs, 350);
      expect(m.avgReactionMs, 350);
    });

    test('reaction clocked from ACT, not drill start', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(3000)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(3400)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 400, timestamp: _t(3400)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(3500)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.drawMs, 400);
      expect(m.engagements.first.reactionMs, 400);
    });
  });

  group('MetricsEngine.compute — multiple engagements', () {
    List<SessionEvent> twoTargetEvents() => [
      SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(1000)),
      SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(1300)),
      SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 300, timestamp: _t(1300)),
      SessionEvent(type: EventType.targetActivated, targetId: 2, requiredHits: 1, timestamp: _t(2000)),
      SessionEvent(type: EventType.hitDetected, targetId: 2, hitNumber: 1, requiredHits: 1, timestamp: _t(2250)),
      SessionEvent(type: EventType.targetComplete, targetId: 2, totalTimeMs: 250, timestamp: _t(2250)),
      SessionEvent(type: EventType.drillFinished, timestamp: _t(2500)),
    ];

    test('produces one engagement per ACT', () {
      final m = MetricsEngine.compute(sid, twoTargetEvents());
      expect(m.engagements, hasLength(2));
    });

    test('per-engagement reaction is correct', () {
      final m = MetricsEngine.compute(sid, twoTargetEvents());
      expect(m.engagements[0].reactionMs, 300);
      expect(m.engagements[1].reactionMs, 250);
    });

    test('avgReactionMs is mean of per-engagement reactions', () {
      final m = MetricsEngine.compute(sid, twoTargetEvents());
      expect(m.avgReactionMs, 275);
    });

    test('preceding delay for first engagement is 0', () {
      final m = MetricsEngine.compute(sid, twoTargetEvents());
      expect(m.engagements[0].precedingDelayMs, 0);
    });

    test('preceding delay for second engagement = ACT(2) - DONE(1)', () {
      final m = MetricsEngine.compute(sid, twoTargetEvents());
      // ACT(t2)=2000, DONE(t1)=1300 → delay=700
      expect(m.engagements[1].precedingDelayMs, 700);
    });

    test('no transition when preceding delay > threshold (700ms > 150ms)', () {
      final m = MetricsEngine.compute(sid, twoTargetEvents());
      expect(m.avgTransitionMs, isNull);
    });

    test('transition computed when preceding delay <= threshold', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(1000)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(1300)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 300, timestamp: _t(1300)),
        SessionEvent(type: EventType.targetActivated, targetId: 2, requiredHits: 1, timestamp: _t(1310)),
        SessionEvent(type: EventType.hitDetected, targetId: 2, hitNumber: 1, requiredHits: 1, timestamp: _t(1500)),
        SessionEvent(type: EventType.targetComplete, targetId: 2, totalTimeMs: 190, timestamp: _t(1500)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(1600)),
      ];
      final m = MetricsEngine.compute(sid, events);
      // transition = HIT(t2).first - HIT(t1).last = 1500 - 1300 = 200
      expect(m.avgTransitionMs, 200);
    });
  });

  group('MetricsEngine.compute — splits', () {
    test('split time computed for multi-hit engagement', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 2, timestamp: _t(1000)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 2, timestamp: _t(1300)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 2, requiredHits: 2, timestamp: _t(1500)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 500, timestamp: _t(1500)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(2000)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.avgSplitMs, 200);
    });

    test('no split when single hit per target', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(1000)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(1300)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 300, timestamp: _t(1300)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(2000)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.avgSplitMs, isNull);
    });
  });

  group('MetricsEngine.compute — totals and quality', () {
    test('totalRoundsFired counts only HIT events, not NS violations', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 2, timestamp: _t(1000)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 2, timestamp: _t(1200)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 2, requiredHits: 2, timestamp: _t(1400)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 400, timestamp: _t(1400)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(2000)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.totalRoundsFired, 2);
    });

    test('noShootCount and lateHitCount are correct', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(1000)),
        SessionEvent(type: EventType.noShootViolation, targetId: 1, timestamp: _t(1100)),
        SessionEvent(type: EventType.lateHit, targetId: 1, timestamp: _t(1200)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(1300)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 300, timestamp: _t(1300)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(2000)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.noShootCount, 1);
      expect(m.lateHitCount, 1);
      expect(m.engagements.first.wasNoShoot, isTrue);
      expect(m.engagements.first.hadLateHit, isTrue);
    });

    test('totalDurationMs = first ACT to FIN', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(1000)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(1300)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 300, timestamp: _t(1300)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(4000)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.totalDurationMs, 3000);
    });

    test('dataQualityWarning set when engagement has no hits and no DONE', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(1000)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(5000)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.dataQualityWarning, isTrue);
    });
  });

  group('MetricsEngine.compute — transition threshold boundary', () {
    // Helper: two-target events with configurable delay between DONE(1) and ACT(2)
    List<SessionEvent> twoTargetWithDelay(int delayMs) => [
      SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(0)),
      SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(200)),
      SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 200, timestamp: _t(200)),
      SessionEvent(type: EventType.targetActivated, targetId: 2, requiredHits: 1, timestamp: _t(200 + delayMs)),
      SessionEvent(type: EventType.hitDetected, targetId: 2, hitNumber: 1, requiredHits: 1, timestamp: _t(200 + delayMs + 180)),
      SessionEvent(type: EventType.targetComplete, targetId: 2, totalTimeMs: 180, timestamp: _t(200 + delayMs + 180)),
      SessionEvent(type: EventType.drillFinished, timestamp: _t(200 + delayMs + 300)),
    ];

    test('exactly at threshold (150ms) counts as a transition', () {
      final m = MetricsEngine.compute(sid, twoTargetWithDelay(150));
      // preceding delay == threshold → transition = HIT(t2).first - HIT(t1).last
      // = (200 + 150 + 180) - 200 = 330
      expect(m.avgTransitionMs, 330);
    });

    test('one ms above threshold (151ms) — no transition, returns null', () {
      final m = MetricsEngine.compute(sid, twoTargetWithDelay(151));
      expect(m.avgTransitionMs, isNull);
    });
  });

  group('MetricsEngine.compute — aborted drill (no FIN event)', () {
    test('handles event stream with no FIN — partial metrics still computed', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(1000)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(1300)),
        // No DONE, no FIN — drill was aborted mid-run
      ];
      final m = MetricsEngine.compute(sid, events);
      // Reaction is still computable
      expect(m.engagements, hasLength(1));
      expect(m.engagements.first.reactionMs, 300);
      expect(m.totalRoundsFired, 1);
      // Duration is null — no FIN event
      expect(m.totalDurationMs, isNull);
      // No crash
    });
  });

  group('MetricsEngine.compute — median and stddev', () {
    test('medianReactionMs with odd count', () {
      // reactions: 200, 300, 400 → median = 300
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(0)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(200)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 200, timestamp: _t(200)),
        SessionEvent(type: EventType.targetActivated, targetId: 2, requiredHits: 1, timestamp: _t(200)),
        SessionEvent(type: EventType.hitDetected, targetId: 2, hitNumber: 1, requiredHits: 1, timestamp: _t(500)),
        SessionEvent(type: EventType.targetComplete, targetId: 2, totalTimeMs: 300, timestamp: _t(500)),
        SessionEvent(type: EventType.targetActivated, targetId: 3, requiredHits: 1, timestamp: _t(500)),
        SessionEvent(type: EventType.hitDetected, targetId: 3, hitNumber: 1, requiredHits: 1, timestamp: _t(900)),
        SessionEvent(type: EventType.targetComplete, targetId: 3, totalTimeMs: 400, timestamp: _t(900)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(1000)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.medianReactionMs, 300);
    });

    test('stddevReactionMs with uniform reactions is 0', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(0)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(300)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 300, timestamp: _t(300)),
        SessionEvent(type: EventType.targetActivated, targetId: 2, requiredHits: 1, timestamp: _t(300)),
        SessionEvent(type: EventType.hitDetected, targetId: 2, hitNumber: 1, requiredHits: 1, timestamp: _t(600)),
        SessionEvent(type: EventType.targetComplete, targetId: 2, totalTimeMs: 300, timestamp: _t(600)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(700)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.stddevReactionMs, 0);
    });
  });
}
