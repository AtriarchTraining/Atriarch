import 'package:atriarch/data/in_memory_repositories.dart';
import 'package:atriarch/data/session_summary.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/screens/recent_drills_screen.dart';
import 'package:atriarch/screens/results_screen.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/util/drill_log_codec.dart';
import 'package:atriarch/models/drill_session.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Mounts [child] inside a MaterialApp with [AppState] provided, and returns
/// the state so tests can mutate the in-memory repositories directly.
Future<AppState> _pumpWithState(
  WidgetTester tester,
  Widget child, {
  AppState? state,
}) async {
  final s = state ?? AppState.forTest();
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: s,
      child: MaterialApp(
        theme: buildAtriarchLightTheme(),
        home: child,
      ),
    ),
  );
  return s;
}

void main() {
  testWidgets('empty session shows empty-state copy', (tester) async {
    final state = await _pumpWithState(tester, const RecentDrillsScreen());
    expect(
      find.text('No drills completed yet this session.'),
      findsOneWidget,
    );
    state.dispose();
  });

  testWidgets('two sessions render in reverse-chrono order', (tester) async {
    final state = AppState.forTest();
    final sessions = state.sessions as InMemorySessionRepository;
    await sessions.appendDrill(SessionSummary.create(
      drillId: 'older',
      presetName: 'Old Preset',
      startedAt: DateTime(2026, 4, 20, 10, 0),
      duration: const Duration(minutes: 2),
      completions: 5,
      violations: 0,
      lateHits: 0,
    ));
    await sessions.appendDrill(SessionSummary.create(
      drillId: 'newer',
      presetName: 'New Preset',
      startedAt: DateTime(2026, 4, 20, 14, 30),
      duration: const Duration(minutes: 3),
      completions: 12,
      violations: 0,
      lateHits: 0,
    ));

    await _pumpWithState(tester, const RecentDrillsScreen(), state: state);

    // Both rows exist and "New Preset" is above "Old Preset" in the tree.
    final newPresetTop = tester.getTopLeft(find.text('New Preset')).dy;
    final oldPresetTop = tester.getTopLeft(find.text('Old Preset')).dy;
    expect(newPresetTop, lessThan(oldPresetTop));
    state.dispose();
  });

  testWidgets('tap row opens ResultsScreen in readOnly mode', (tester) async {
    final state = AppState.forTest();
    final sessions = state.sessions as InMemorySessionRepository;
    final logs = state.drillLogs as InMemoryDrillLogRepository;

    // Build a real drill log payload so RecentDrillsScreen can decode it.
    final session = DrillSession(
      config: DrillConfig(programType: ProgramType.programB),
      drillId: 'drill-abc',
      startTime: DateTime(2026, 4, 20, 14, 30),
    );
    session.addEvent(SessionEvent(
      type: EventType.targetActivated,
      targetId: 1,
      timestamp: DateTime(2026, 4, 20, 14, 30, 1),
    ));
    session.addEvent(SessionEvent(
      type: EventType.drillFinished,
      timestamp: DateTime(2026, 4, 20, 14, 30, 5),
    ));
    await logs.writeLog(
      'drill-abc',
      DrillLogCodec.encode(session, presetName: 'Tap Test'),
    );

    await sessions.appendDrill(SessionSummary.create(
      drillId: 'drill-abc',
      presetName: 'Tap Test',
      startedAt: DateTime(2026, 4, 20, 14, 30),
      duration: const Duration(seconds: 4),
      completions: 0,
      violations: 0,
      lateHits: 0,
    ));

    await _pumpWithState(tester, const RecentDrillsScreen(), state: state);
    await tester.tap(find.text('Tap Test'));
    await tester.pumpAndSettle();

    // A new ResultsScreen is on top of the navigator and is readOnly.
    final results = tester.widget<ResultsScreen>(find.byType(ResultsScreen));
    expect(results.readOnly, isTrue);
    expect(results.viewModel, isNotNull);
    expect(results.viewModel!.drillId, equals('drill-abc'));

    // Read-only hides no buttons beyond the home FAB — we assert Run Again
    // never appears in live or historical (it doesn't exist in this app).
    // Sanity: the AppBar share icon is still there.
    expect(find.byIcon(Icons.ios_share), findsOneWidget);

    state.dispose();
  });
}
