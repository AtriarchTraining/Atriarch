import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/home_screen.dart';

void main() {
  testWidgets('renders three tactical program rows', (tester) async {
    final state = AppState()..setOnboardingCompleteForTesting(true);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('TARGET_SETUP'), findsOneWidget);
    expect(find.text('PROGRAM_A'), findsOneWidget);
    expect(find.text('PROGRAM_B'), findsOneWidget);
  });
}
