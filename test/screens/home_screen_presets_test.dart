import 'package:atriarch/repositories/drill_template_repository.dart';
import 'package:atriarch/screens/home_screen.dart';
import 'package:atriarch/screens/preset_manager_screen.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_drill_template_repository.dart';
import '../test_helpers/fake_preferences_repository.dart';

const _testSurface = Size(800, 1200);

Widget _wrapHome({FakeDrillTemplateRepository? templateRepo}) {
  final prefs = FakePreferencesRepository();
  final repo = templateRepo ?? FakeDrillTemplateRepository();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>(
        create: (_) {
          final state = AppState(
            preferences: prefs,
          );
          state.setOnboardingCompleteForTesting(true);
          return state;
        },
      ),
      Provider<DrillTemplateRepository>.value(value: repo),
    ],
    child: const MaterialApp(
      home: HomeScreen(),
    ),
  );
}

void main() {
  group('HomeScreen PRESETS entry', () {
    testWidgets('PRESETS button is visible', (tester) async {
      await tester.binding.setSurfaceSize(_testSurface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_wrapHome());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('PRESETS'), 100);
      expect(find.text('PRESETS'), findsOneWidget);
    });

    testWidgets('tapping PRESETS navigates to PresetManagerScreen',
        (tester) async {
      await tester.binding.setSurfaceSize(_testSurface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrapHome(templateRepo: FakeDrillTemplateRepository()),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('PRESETS'), 100);
      await tester.tap(find.text('PRESETS'));
      await tester.pumpAndSettle();

      expect(find.byType(PresetManagerScreen), findsOneWidget);
    });
  });
}
