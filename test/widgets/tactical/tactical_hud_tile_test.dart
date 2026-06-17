import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_hud_tile.dart';

void main() {
  testWidgets('renders label and value', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: const Scaffold(
          body: TacticalHudTile(label: 'hits', value: '12'),
        ),
      ),
    );
    expect(find.text('HITS'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });
}
