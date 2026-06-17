import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:atriarch/repositories/drill_template_repository.dart';
import 'package:atriarch/screens/program_a_setup_screen.dart';
import 'package:atriarch/services/preferences_repository.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/state/shooter_state.dart';

import '../helpers/fake_repositories.dart';
import '../test_helpers/fake_drill_template_repository.dart';
import '../test_helpers/fake_preferences_repository.dart';
import '../test_helpers/fake_shooter_repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seeds initial groups from AppState.buildSeededGroups()',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'target_groups': '{"7":1,"8":1,"9":2}',
      'target_group_labels': '{"1":"Left bank"}',
      'target_group_order': '1,2',
    });
    final prefs = PreferencesRepository(await SharedPreferences.getInstance());
    final state = AppState.forTesting(
      sessions: FakeSessionRepository(),
      shooterState: FakeShooterState(),
      preferences: prefs,
    );
    await state.hydratePreferences();

    final shooterRepo = FakeShooterRepo([]);
    final shooterState = ShooterState(shooterRepo);
    await shooterState.initialize();

    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<ShooterState>.value(value: shooterState),
          Provider<DrillTemplateRepository>.value(
            value: FakeDrillTemplateRepository(),
          ),
          Provider<PreferencesRepository>.value(
            value: FakePreferencesRepository(),
          ),
        ],
        child: const MaterialApp(home: ProgramASetupScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // The seed should produce 2 groups with custom name "Left bank" for G1.
    expect(state.buildSeededGroups(), hasLength(2));
    expect(state.buildSeededGroups()[0].name, 'Left bank');
    // Smoke-check: the screen rendered without crashing and shows content.
    expect(find.byType(ProgramASetupScreen), findsOneWidget);
  });
}
