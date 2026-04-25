import 'package:atriarch/models/target_breakdown.dart';
import 'package:atriarch/screens/target_breakdown_screen.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_metrics_repository.dart';

Widget _wrap(Widget child, {FakeMetricsRepository? repo}) {
  return MaterialApp(
    home: ChangeNotifierProvider<AppState>(
      create: (_) => AppState(metricsRepo: repo),
      child: child,
    ),
  );
}

void main() {
  group('TargetBreakdownScreen', () {
    testWidgets('shows empty-state message when no data', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TargetBreakdownScreen(),
          repo: FakeMetricsRepository(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('NO TARGET DATA'), findsOneWidget);
    });

    testWidgets('shows null-repo message when metricsRepo is absent',
        (tester) async {
      await tester.pumpWidget(_wrap(const TargetBreakdownScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('NO TARGET DATA'), findsOneWidget);
    });

    testWidgets('renders one row per target sorted slowest-first',
        (tester) async {
      final repo = FakeMetricsRepository(
        breakdowns: const [
          TargetBreakdown(
            targetId: 2,
            avgReactionMs: 510,
            totalHits: 4,
            totalRequired: 4,
            noShootCount: 0,
            lateHitCount: 0,
            totalEngagements: 2,
          ),
          TargetBreakdown(
            targetId: 1,
            avgReactionMs: 310,
            totalHits: 3,
            totalRequired: 4,
            noShootCount: 0,
            lateHitCount: 1,
            totalEngagements: 2,
          ),
        ],
      );
      await tester.pumpWidget(
        _wrap(const TargetBreakdownScreen(), repo: repo),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('NODE_T2'), findsOneWidget);
      expect(find.textContaining('NODE_T1'), findsOneWidget);
      expect(find.textContaining('510MS'), findsOneWidget);
      expect(find.textContaining('310MS'), findsOneWidget);
      expect(find.textContaining('HIT%'), findsWidgets);
      expect(find.textContaining('75'), findsWidgets);

      final t2Offset = tester.getTopLeft(find.textContaining('NODE_T2'));
      final t1Offset = tester.getTopLeft(find.textContaining('NODE_T1'));
      expect(t2Offset.dy, lessThan(t1Offset.dy));
    });

    testWidgets('violation accent visible when noShootCount > 0',
        (tester) async {
      final repo = FakeMetricsRepository(
        breakdowns: const [
          TargetBreakdown(
            targetId: 3,
            avgReactionMs: 400,
            totalHits: 1,
            totalRequired: 2,
            noShootCount: 2,
            lateHitCount: 0,
            totalEngagements: 1,
          ),
        ],
      );
      await tester.pumpWidget(
        _wrap(const TargetBreakdownScreen(), repo: repo),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('NS'), findsWidgets);
    });

    testWidgets('late accent visible when lateHitCount > 0', (tester) async {
      final repo = FakeMetricsRepository(
        breakdowns: const [
          TargetBreakdown(
            targetId: 4,
            avgReactionMs: 350,
            totalHits: 2,
            totalRequired: 2,
            noShootCount: 0,
            lateHitCount: 3,
            totalEngagements: 2,
          ),
        ],
      );
      await tester.pumpWidget(
        _wrap(const TargetBreakdownScreen(), repo: repo),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('LATE'), findsWidgets);
    });
  });
}
