import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/state/shooter_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/program_b_setup_screen.dart';
import 'package:atriarch/widgets/tactical/tactical_min_max_card.dart';
import 'package:atriarch/widgets/tactical/tactical_primary_button.dart';
import '../test_helpers/fake_shooter_repo.dart';

void main() {
  testWidgets('renders 3 MinMaxCards and primary start button',
      (tester) async {
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
        ],
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const ProgramBSetupScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TacticalMinMaxCard), findsNWidgets(3));
    expect(find.byType(TacticalPrimaryButton), findsWidgets);
    expect(find.text('START DELAY'), findsOneWidget);
    expect(find.text('TIME BETWEEN ACTIVATIONS'), findsOneWidget);
    expect(find.text('REQUIRED HITS'), findsOneWidget);
  });
}
