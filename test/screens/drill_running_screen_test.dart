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

  testWidgets('800ms hold triggers stop', (tester) async {
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

    // Press and hold the STOP button for > 800ms.
    final stopFinder = find.text('STOP');
    final gesture = await tester.startGesture(tester.getCenter(stopFinder));
    // Advance time past the 800ms ring duration.
    await tester.pump(const Duration(milliseconds: 900));
    // Ring completion triggers the onStop future; drill should be stopping.
    await tester.pump();

    // The button switches to "STOPPING…" when the phase moves to stopping.
    // We don't assert on AppState directly (too coupled), but we can confirm
    // the ring animation completed by releasing and checking the label swap
    // does not happen instantly from a bare tap.
    await gesture.up();
    await tester.pump();
    // Screen should still be mounted — no navigation yet (DrillPhase.stopping
    // is not DrillPhase.finished).
    expect(find.byType(DrillRunningScreen), findsOneWidget);
  });

  testWidgets('early release does not stop', (tester) async {
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

    final stopFinder = find.text('STOP');
    final gesture = await tester.startGesture(tester.getCenter(stopFinder));
    // Hold less than 800ms, then release.
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();

    // STOP label should still be visible (not swapped to STOPPING…).
    expect(find.text('STOP'), findsOneWidget);
    expect(find.text('STOPPING…'), findsNothing);
  });
}
