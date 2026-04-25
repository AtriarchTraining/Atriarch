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

  group('MetricsEngine.compute — Program B concurrent targets', () {
    // Two targets activated simultaneously; hits and completions interleave.
    // Timeline:
    //   t=0    ACT/1  (target 1 activates)
    //   t=50   ACT/2  (target 2 activates while target 1 still live)
    //   t=300  HIT/1  (target 1 first hit)
    //   t=350  HIT/2  (target 2 first hit)
    //   t=300  DONE/1 (target 1 complete, totalTimeMs=300)
    //   t=400  HIT/2  (target 2 second hit — 2-hit engagement)
    //   t=400  DONE/2 (target 2 complete, totalTimeMs=350)
    //   t=500  FIN
    List<SessionEvent> twoTargetConcurrent() => [
      SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(0)),
      SessionEvent(type: EventType.targetActivated, targetId: 2, requiredHits: 2, timestamp: _t(50)),
      SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(300)),
      SessionEvent(type: EventType.hitDetected, targetId: 2, hitNumber: 1, requiredHits: 2, timestamp: _t(350)),
      SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 300, timestamp: _t(300)),
      SessionEvent(type: EventType.hitDetected, targetId: 2, hitNumber: 2, requiredHits: 2, timestamp: _t(400)),
      SessionEvent(type: EventType.targetComplete, targetId: 2, totalTimeMs: 350, timestamp: _t(400)),
      SessionEvent(type: EventType.drillFinished, timestamp: _t(500)),
    ];

    test('produces one engagement per target, not one per ACT flush', () {
      final m = MetricsEngine.compute(sid, twoTargetConcurrent());
      expect(m.engagements, hasLength(2));
    });

    test('target 1 reaction is correctly computed from its own ACT', () {
      final m = MetricsEngine.compute(sid, twoTargetConcurrent());
      final e1 = m.engagements.firstWhere((e) => e.targetId == 1);
      expect(e1.reactionMs, 300); // HIT(t=300) - ACT(t=0)
    });

    test('target 2 reaction is correctly computed from its own ACT', () {
      final m = MetricsEngine.compute(sid, twoTargetConcurrent());
      final e2 = m.engagements.firstWhere((e) => e.targetId == 2);
      expect(e2.reactionMs, 300); // HIT(t=350) - ACT(t=50)
    });

    test('target 1 hitsLanded is 1, not 0', () {
      final m = MetricsEngine.compute(sid, twoTargetConcurrent());
      final e1 = m.engagements.firstWhere((e) => e.targetId == 1);
      expect(e1.hitsLanded, 1);
    });

    test('target 2 hitsLanded is 2 (multi-hit concurrent engagement)', () {
      final m = MetricsEngine.compute(sid, twoTargetConcurrent());
      final e2 = m.engagements.firstWhere((e) => e.targetId == 2);
      expect(e2.hitsLanded, 2);
    });

    test('totalRoundsFired counts all hits from all concurrent targets', () {
      final m = MetricsEngine.compute(sid, twoTargetConcurrent());
      expect(m.totalRoundsFired, 3); // 1 hit on T1 + 2 hits on T2
    });

    test('no dataQualityWarning when all targets receive hits', () {
      final m = MetricsEngine.compute(sid, twoTargetConcurrent());
      expect(m.dataQualityWarning, isFalse);
    });

    test('target 1 engagementTimeMs is set from DONE', () {
      final m = MetricsEngine.compute(sid, twoTargetConcurrent());
      final e1 = m.engagements.firstWhere((e) => e.targetId == 1);
      expect(e1.engagementTimeMs, 300); // DONE(t=300) - ACT(t=0)
    });

    test('target 2 engagementTimeMs is set from DONE', () {
      final m = MetricsEngine.compute(sid, twoTargetConcurrent());
      final e2 = m.engagements.firstWhere((e) => e.targetId == 2);
      expect(e2.engagementTimeMs, 350); // DONE(t=400) - ACT(t=50)
    });

    test('avgSplitMs for multi-hit target 2 is correct', () {
      final m = MetricsEngine.compute(sid, twoTargetConcurrent());
      // T2: HIT1=350, HIT2=400 → split=50
      expect(m.avgSplitMs, 50);
    });

    test('draw_ms is still first global ACT to first global HIT', () {
      final m = MetricsEngine.compute(sid, twoTargetConcurrent());
      // first ACT=t0, first HIT=t300 (T1)
      expect(m.drawMs, 300);
    });

    // Three targets — tests that the engine handles more than 2 simultaneous.
    test('three concurrent targets each produce correct engagement', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(0)),
        SessionEvent(type: EventType.targetActivated, targetId: 2, requiredHits: 1, timestamp: _t(20)),
        SessionEvent(type: EventType.targetActivated, targetId: 3, requiredHits: 1, timestamp: _t(40)),
        SessionEvent(type: EventType.hitDetected, targetId: 3, hitNumber: 1, requiredHits: 1, timestamp: _t(280)),
        SessionEvent(type: EventType.targetComplete, targetId: 3, totalTimeMs: 240, timestamp: _t(280)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(310)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 310, timestamp: _t(310)),
        SessionEvent(type: EventType.hitDetected, targetId: 2, hitNumber: 1, requiredHits: 1, timestamp: _t(340)),
        SessionEvent(type: EventType.targetComplete, targetId: 2, totalTimeMs: 320, timestamp: _t(340)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(500)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.engagements, hasLength(3));
      expect(m.totalRoundsFired, 3);
      expect(m.dataQualityWarning, isFalse);
      final e1 = m.engagements.firstWhere((e) => e.targetId == 1);
      final e2 = m.engagements.firstWhere((e) => e.targetId == 2);
      final e3 = m.engagements.firstWhere((e) => e.targetId == 3);
      expect(e1.reactionMs, 310);
      expect(e2.reactionMs, 320);
      expect(e3.reactionMs, 240);
      expect(e1.hitsLanded, 1);
      expect(e2.hitsLanded, 1);
      expect(e3.hitsLanded, 1);
    });

    test('no-shoot violation attributed to correct concurrent target', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(0)),
        SessionEvent(type: EventType.targetActivated, targetId: 2, requiredHits: 1, timestamp: _t(10)),
        SessionEvent(type: EventType.noShootViolation, targetId: 2, timestamp: _t(100)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(300)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 300, timestamp: _t(300)),
        SessionEvent(type: EventType.targetComplete, targetId: 2, totalTimeMs: 290, timestamp: _t(300)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(400)),
      ];
      final m = MetricsEngine.compute(sid, events);
      final e1 = m.engagements.firstWhere((e) => e.targetId == 1);
      final e2 = m.engagements.firstWhere((e) => e.targetId == 2);
      expect(e1.wasNoShoot, isFalse);
      expect(e2.wasNoShoot, isTrue);
      expect(m.noShootCount, 1);
    });

    test('second iteration of same target creates a new engagement', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(0)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(300)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 300, timestamp: _t(300)),
        // 800ms inter-activation delay (> transition threshold)
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(1100)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(1420)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 320, timestamp: _t(1420)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(1500)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.engagements, hasLength(2));
      expect(m.engagements[0].targetId, 1);
      expect(m.engagements[1].targetId, 1);
      expect(m.engagements[0].reactionMs, 300);
      expect(m.engagements[1].reactionMs, 320);
      expect(m.engagements[1].precedingDelayMs, 800);
    });

    test('same target fires twice concurrently with another target', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(0)),
        SessionEvent(type: EventType.targetActivated, targetId: 2, requiredHits: 1, timestamp: _t(30)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(300)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 300, timestamp: _t(300)),
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(800)),
        SessionEvent(type: EventType.hitDetected, targetId: 2, hitNumber: 1, requiredHits: 1, timestamp: _t(850)),
        SessionEvent(type: EventType.targetComplete, targetId: 2, totalTimeMs: 820, timestamp: _t(850)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(1100)),
        SessionEvent(type: EventType.targetComplete, targetId: 1, totalTimeMs: 300, timestamp: _t(1100)),
        SessionEvent(type: EventType.drillFinished, timestamp: _t(1200)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.engagements, hasLength(3));
      expect(m.totalRoundsFired, 3);
      expect(m.dataQualityWarning, isFalse);
    });

    test('aborted Program B drill — active concurrent targets get partial engagements', () {
      final events = [
        SessionEvent(type: EventType.targetActivated, targetId: 1, requiredHits: 1, timestamp: _t(0)),
        SessionEvent(type: EventType.targetActivated, targetId: 2, requiredHits: 1, timestamp: _t(50)),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1, timestamp: _t(300)),
        // No DONE for either target — drill aborted
        SessionEvent(type: EventType.drillFinished, timestamp: _t(400)),
      ];
      final m = MetricsEngine.compute(sid, events);
      expect(m.engagements, hasLength(2));
      final e1 = m.engagements.firstWhere((e) => e.targetId == 1);
      final e2 = m.engagements.firstWhere((e) => e.targetId == 2);
      expect(e1.reactionMs, 300);
      expect(e2.reactionMs, isNull);
      expect(m.dataQualityWarning, isTrue);
    });
  });
}
