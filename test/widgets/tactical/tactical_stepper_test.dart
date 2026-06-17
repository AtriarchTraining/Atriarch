import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_stepper.dart';

void main() {
  testWidgets('increments on + tap', (tester) async {
    final ctrl = TextEditingController(text: '1.00');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: TacticalStepper(
            controller: ctrl,
            label: 'test',
            step: 0.25,
            unit: 'sec',
          ),
        ),
      ),
    );
    expect(find.text('1.00'), findsOneWidget);
    expect(find.text('SEC'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(ctrl.text, '1.25');

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(ctrl.text, '1.00');
  });

  testWidgets('compact variant renders unit label', (tester) async {
    final ctrl = TextEditingController(text: '0.50');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: TacticalStepper(
            controller: ctrl,
            label: 'min',
            step: 0.25,
            unit: 'sec',
            compact: true,
          ),
        ),
      ),
    );
    expect(find.text('MIN'), findsOneWidget);
    expect(find.text('0.50'), findsOneWidget);
  });
}
