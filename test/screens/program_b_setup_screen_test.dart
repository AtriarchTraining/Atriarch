import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/program_b_setup_screen.dart';
import 'package:atriarch/widgets/tactical/tactical_min_max_card.dart';
import 'package:atriarch/widgets/tactical/tactical_primary_button.dart';

void main() {
  testWidgets('renders 3 MinMaxCards and primary start button',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
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
