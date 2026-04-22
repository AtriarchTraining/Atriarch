import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_min_max_card.dart';
import 'package:atriarch/widgets/tactical/tactical_stepper.dart';

void main() {
  testWidgets('renders title + two steppers', (tester) async {
    final minCtrl = TextEditingController(text: '0.50');
    final maxCtrl = TextEditingController(text: '2.00');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: TacticalMinMaxCard(
            title: 'START DELAY',
            rangeHint: '0.00 – 10.00 SEC',
            minController: minCtrl,
            maxController: maxCtrl,
            step: 0.25,
            unit: 'sec',
          ),
        ),
      ),
    );
    expect(find.text('START DELAY'), findsOneWidget);
    expect(find.text('0.00 – 10.00 SEC'), findsOneWidget);
    expect(find.byType(TacticalStepper), findsNWidgets(2));
  });
}
