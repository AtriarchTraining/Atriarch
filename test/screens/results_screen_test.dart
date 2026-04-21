import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/results_screen.dart';

void main() {
  testWidgets('shows empty state when no session', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const ResultsScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('No session data.'), findsOneWidget);
  });
}
