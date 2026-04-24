import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_section.dart';

void main() {
  testWidgets('renders code and trailing labels uppercase', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: const Scaffold(
          body: TacticalSection(
            code: 'param_01',
            trailing: 'timing',
          ),
        ),
      ),
    );
    expect(find.text('PARAM_01'), findsOneWidget);
    expect(find.text('TIMING'), findsOneWidget);
  });
}
