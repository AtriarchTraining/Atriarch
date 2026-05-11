import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/state/shooter_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/repositories/drill_template_repository.dart';
import 'package:atriarch/screens/program_a_setup_screen.dart';
import 'package:atriarch/services/preferences_repository.dart';
import 'package:atriarch/models/target_unit.dart';
import 'package:atriarch/widgets/tactical/group_node_card.dart';
import 'package:atriarch/widgets/tactical/tactical_min_max_card.dart';
import '../test_helpers/fake_drill_template_repository.dart';
import '../test_helpers/fake_preferences_repository.dart';
import '../test_helpers/fake_shooter_repo.dart';

void main() {
  testWidgets('renders 5 GroupNodeCards and 3 MinMaxCards', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = FakeShooterRepo([makeUnassignedShooter()]);
    final shooterState = ShooterState(repo);
    await shooterState.initialize();

    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>(create: (_) => AppState()),
          ChangeNotifierProvider<ShooterState>.value(value: shooterState),
          Provider<DrillTemplateRepository>.value(
            value: FakeDrillTemplateRepository(),
          ),
          Provider<PreferencesRepository>.value(
            value: FakePreferencesRepository(),
          ),
        ],
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const ProgramASetupScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GroupNodeCard), findsNWidgets(5));
    expect(find.byType(TacticalMinMaxCard), findsNWidgets(3));
  });

  testWidgets('tapping a group card opens the bottom sheet',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = FakeShooterRepo([makeUnassignedShooter()]);
    final shooterState = ShooterState(repo);
    await shooterState.initialize();
    final appState = AppState()
      ..targets = [TargetUnit(id: 1, isOnline: true)];

    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<ShooterState>.value(value: shooterState),
          Provider<DrillTemplateRepository>.value(
            value: FakeDrillTemplateRepository(),
          ),
          Provider<PreferencesRepository>.value(
            value: FakePreferencesRepository(),
          ),
        ],
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const ProgramASetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the first group card via its GROUP 01 label.
    await tester.tap(find.text('GROUP 01').first);
    await tester.pumpAndSettle();

    expect(find.text('GROUP 01 — TARGETS'), findsOneWidget);
    expect(find.text('AVAILABLE'), findsOneWidget);
  });

  testWidgets('SnackBar with UNDO appears after adding a target',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = FakeShooterRepo([makeUnassignedShooter()]);
    final shooterState = ShooterState(repo);
    await shooterState.initialize();
    final appState = AppState()
      ..targets = [TargetUnit(id: 2, isOnline: true)];

    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<ShooterState>.value(value: shooterState),
          Provider<DrillTemplateRepository>.value(
            value: FakeDrillTemplateRepository(),
          ),
          Provider<PreferencesRepository>.value(
            value: FakePreferencesRepository(),
          ),
        ],
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const ProgramASetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('GROUP 01').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('T/U_02'));
    await tester.pumpAndSettle();

    expect(find.text('UNDO'), findsOneWidget);
  });

  testWidgets('phase change auto-dismisses the sheet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = FakeShooterRepo([makeUnassignedShooter()]);
    final shooterState = ShooterState(repo);
    await shooterState.initialize();
    final appState = AppState()
      ..targets = [TargetUnit(id: 1, isOnline: true)];

    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<ShooterState>.value(value: shooterState),
          Provider<DrillTemplateRepository>.value(
            value: FakeDrillTemplateRepository(),
          ),
          Provider<PreferencesRepository>.value(
            value: FakePreferencesRepository(),
          ),
        ],
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const ProgramASetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('GROUP 01').first);
    await tester.pumpAndSettle();
    expect(find.text('GROUP 01 — TARGETS'), findsOneWidget);

    appState.setPhaseForTesting(DrillPhase.arming);
    // pumpAndSettle would time out due to the loading animation on the arming
    // button; pump a fixed number of frames instead — sufficient for the sheet
    // pop animation to complete.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('GROUP 01 — TARGETS'), findsNothing);
  });
}
