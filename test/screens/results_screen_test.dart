import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/constants.dart';
import 'package:atriarch/models/computed_metrics.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/drill_session.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/results_screen.dart';

void main() {
  testWidgets('shows empty state when no session', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const ResultsScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('No session data.'), findsOneWidget);
  });

  group('timing section', () {
    testWidgets('shows timing tiles when currentMetrics is set', (tester) async {
      final state = AppState();
      state.currentSession = DrillSession(
        config: DrillConfig(
          programType: ProgramType.programA,
          startMin: 1.0,
          startMax: 2.0,
          delayMin: 0.0,
          delayMax: 0.0,
          hitsMin: 1,
          hitsMax: 1,
          iterations: 1,
        ),
      );
      state.setCurrentMetricsForTesting(ComputedMetrics(
        sessionId: 'test',
        drawMs: 350,
        totalRoundsFired: 3,
        noShootCount: 0,
        lateHitCount: 0,
        avgReactionMs: 310,
        avgTransitionMs: 420,
        metricsVersion: kMetricsVersion,
        engagements: const [],
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: buildAtriarchDarkTheme(),
            home: const ResultsScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('350MS', skipOffstage: false), findsOneWidget);  // draw tile
      expect(find.text('310MS', skipOffstage: false), findsOneWidget);  // avg reaction tile
    });

    testWidgets('hides timing section when currentMetrics is null', (tester) async {
      final state = AppState();
      state.currentSession = DrillSession(
        config: DrillConfig(
          programType: ProgramType.programA,
          startMin: 1.0,
          startMax: 2.0,
          delayMin: 0.0,
          delayMax: 0.0,
          hitsMin: 1,
          hitsMax: 1,
          iterations: 1,
        ),
      );
      // currentMetrics is null (not set)

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: buildAtriarchDarkTheme(),
            home: const ResultsScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('TIMING'), findsNothing);
    });
  });
}
