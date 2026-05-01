import 'package:atriarch/constants.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/drill_session.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/screens/results_screen.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  DrillSession buildSession() {
    final start = DateTime(2026, 4, 30, 10, 0, 0);
    final session = DrillSession(
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
      startTime: start,
    );
    session.addEvent(SessionEvent(
      type: EventType.targetActivated,
      targetId: 1,
      timestamp: start,
    ));
    session.addEvent(SessionEvent(
      type: EventType.hitDetected,
      targetId: 1,
      hitNumber: 1,
      requiredHits: 1,
      timestamp: start.add(const Duration(seconds: 1)),
    ));
    session.addEvent(SessionEvent(
      type: EventType.targetComplete,
      targetId: 1,
      totalTimeMs: 1000,
      timestamp: start.add(const Duration(seconds: 1)),
    ));
    session.addEvent(SessionEvent(
      type: EventType.targetActivated,
      targetId: 2,
      timestamp: start.add(const Duration(seconds: 2)),
    ));
    return session;
  }

  Widget buildApp(AppState state) => ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const ResultsScreen(),
        ),
      );

  testWidgets('Test A — single row expands and shows that unit\'s events inline',
      (tester) async {
    final state = AppState();
    state.currentSession = buildSession();

    await tester.pumpWidget(buildApp(state));
    await tester.pump();

    // Both PER_NODE row labels are present (may be offstage in scrollable list)
    expect(find.text('T/U_01', skipOffstage: false), findsAtLeast(1));
    expect(find.text('T/U_02', skipOffstage: false), findsAtLeast(1));

    // Ensure T/U_01 is visible and tap it to expand
    await tester.ensureVisible(find.text('T/U_01', skipOffstage: false).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('T/U_01', skipOffstage: false).first);
    await tester.pumpAndSettle();

    // T/U_01 events appear twice: once in inline expansion, once in global EVENT_LOG
    expect(
      find.textContaining('T/U_01 activated', skipOffstage: false),
      findsNWidgets(2),
      reason: 'T/U_01 activated should appear in both inline expansion and EVENT_LOG',
    );
    expect(
      find.textContaining('T/U_01 hit 1/1', skipOffstage: false),
      findsNWidgets(2),
      reason: 'T/U_01 hit should appear in both inline expansion and EVENT_LOG',
    );
    expect(
      find.textContaining('T/U_01 complete', skipOffstage: false),
      findsNWidgets(2),
      reason: 'T/U_01 complete should appear in both inline expansion and EVENT_LOG',
    );

    // T/U_02 event appears only once (global EVENT_LOG only — not expanded)
    expect(
      find.textContaining('T/U_02 activated', skipOffstage: false),
      findsOneWidget,
      reason: 'T/U_02 activated should appear only in the global EVENT_LOG',
    );
  });

  testWidgets('Test B — expanding a second row collapses the first',
      (tester) async {
    final state = AppState();
    state.currentSession = buildSession();

    await tester.pumpWidget(buildApp(state));
    await tester.pump();

    // Ensure T/U_01 is visible and tap it to expand
    await tester.ensureVisible(find.text('T/U_01', skipOffstage: false).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('T/U_01', skipOffstage: false).first);
    await tester.pumpAndSettle();

    // Confirm T/U_01 is expanded (appears twice)
    expect(
      find.textContaining('T/U_01 activated', skipOffstage: false),
      findsNWidgets(2),
      reason: 'T/U_01 activated should appear twice after expanding T/U_01',
    );

    // Ensure T/U_02 is visible and tap it to expand (should collapse T/U_01)
    await tester.ensureVisible(find.text('T/U_02', skipOffstage: false).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('T/U_02', skipOffstage: false).first);
    await tester.pumpAndSettle();

    // T/U_01 inline expansion is gone — only global log entry remains
    expect(
      find.textContaining('T/U_01 activated', skipOffstage: false),
      findsOneWidget,
      reason: 'T/U_01 activated should appear only once after collapsing',
    );

    // T/U_02 is now expanded — appears twice
    expect(
      find.textContaining('T/U_02 activated', skipOffstage: false),
      findsNWidgets(2),
      reason: 'T/U_02 activated should appear twice after expanding T/U_02',
    );
  });
}
