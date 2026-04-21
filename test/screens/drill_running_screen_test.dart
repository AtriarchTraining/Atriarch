import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/drill_running_screen.dart';

void main() {
  testWidgets('renders STOP label', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const DrillRunningScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('STOP'), findsOneWidget);
  });

  testWidgets('tap alone does not trigger stop', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const DrillRunningScreen(),
        ),
      ),
    );
    await tester.pump();
    // Single tap — should NOT stop (press-and-hold required).
    await tester.tap(find.text('STOP'));
    await tester.pump(const Duration(milliseconds: 100));
    // After 100ms, drill should still be running. Smoke test only.
    expect(find.text('STOP'), findsOneWidget);
  });

  testWidgets('HUD row renders', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const DrillRunningScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('HITS'), findsOneWidget);
  });
}
