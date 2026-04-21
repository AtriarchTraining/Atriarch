import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/home_screen.dart';

void main() {
  testWidgets('app boots to home screen with dark theme', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('ATRIARCH // HOME'), findsOneWidget);
  });
}
