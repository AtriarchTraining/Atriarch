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

  testWidgets('fires onTap when tapped', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: TacticalCard(
            onTap: () => tapped++,
            child: const Text('TAP_ME'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('TAP_ME'));
    expect(tapped, 1);
  });
}
