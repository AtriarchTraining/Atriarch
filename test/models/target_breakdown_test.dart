// test/models/target_breakdown_test.dart
import 'package:atriarch/models/target_breakdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TargetBreakdown', () {
    test('hitRate returns 0 when totalRequired is 0', () {
      const tb = TargetBreakdown(
        targetId: 1, avgReactionMs: 350, totalHits: 0, totalRequired: 0,
        noShootCount: 0, lateHitCount: 0, totalEngagements: 0,
      );
      expect(tb.hitRate, 0.0);
    });

    test('hitRate computes correctly', () {
      const tb = TargetBreakdown(
        targetId: 2, avgReactionMs: 400, totalHits: 6, totalRequired: 8,
        noShootCount: 1, lateHitCount: 2, totalEngagements: 4,
      );
      expect(tb.hitRate, closeTo(0.75, 0.001));
    });

    test('hasViolations is true when noShootCount > 0', () {
      const tb = TargetBreakdown(
        targetId: 1, avgReactionMs: 300, totalHits: 2, totalRequired: 2,
        noShootCount: 1, lateHitCount: 0, totalEngagements: 1,
      );
      expect(tb.hasViolations, isTrue);
    });

    test('hasViolations is false when noShootCount == 0', () {
      const tb = TargetBreakdown(
        targetId: 1, avgReactionMs: 300, totalHits: 2, totalRequired: 2,
        noShootCount: 0, lateHitCount: 0, totalEngagements: 1,
      );
      expect(tb.hasViolations, isFalse);
    });

    test('fromMap round-trips all fields', () {
      final m = <String, Object?>{
        'target_id': 3, 'avg_reaction_ms': 275.5, 'total_hits': 10,
        'total_required': 12, 'no_shoot_count': 2, 'late_hit_count': 1,
        'total_engagements': 6,
      };
      final tb = TargetBreakdown.fromMap(m);
      expect(tb.targetId, 3);
      expect(tb.avgReactionMs, 276); // rounds
      expect(tb.totalHits, 10);
      expect(tb.totalRequired, 12);
      expect(tb.noShootCount, 2);
      expect(tb.lateHitCount, 1);
      expect(tb.totalEngagements, 6);
    });
  });
}
