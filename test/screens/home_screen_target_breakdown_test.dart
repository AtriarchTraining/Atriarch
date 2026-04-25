import 'package:atriarch/screens/home_screen.dart';
import 'package:atriarch/screens/target_breakdown_screen.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_metrics_repository.dart';
import '../test_helpers/fake_preferences_repository.dart';

Widget _wrapHome({FakeMetricsRepository? repo}) {
  final prefs = FakePreferencesRepository();
  return MaterialApp(
    home: ChangeNotifierProvider<AppState>(
      create: (_) {
        final state = AppState(
          metricsRepo: repo,
          preferences: prefs,
        );
        state.setOnboardingCompleteForTesting(true);
        return state;
      },
      child: const HomeScreen(),
    ),
  );
}

void main() {
  group('HomeScreen TARGET_BREAKDOWN entry', () {
    testWidgets('TARGET_BREAKDOWN button is present', (tester) async {
      await tester.pumpWidget(_wrapHome());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('TARGET_BREAKDOWN'),
        100,
      );
      expect(find.text('TARGET_BREAKDOWN'), findsOneWidget);
    });

    testWidgets('tapping TARGET_BREAKDOWN navigates to TargetBreakdownScreen',
        (tester) async {
      await tester.pumpWidget(
        _wrapHome(repo: FakeMetricsRepository()),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('TARGET_BREAKDOWN'),
        100,
      );
      await tester.tap(find.text('TARGET_BREAKDOWN'));
      await tester.pumpAndSettle();

      expect(find.byType(TargetBreakdownScreen), findsOneWidget);
    });
  });
}
