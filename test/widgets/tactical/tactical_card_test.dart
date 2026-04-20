import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_card.dart';

void main() {
  testWidgets('renders child with accent border', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: const Scaffold(
          body: TacticalCard(
            accent: Colors.blue,
            child: Text('CHILD'),
          ),
        ),
      ),
    );
    expect(find.text('CHILD'), findsOneWidget);
  });
}
