import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_primary_button.dart';

void main() {
  testWidgets('primary renders label and fires onTap', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: TacticalPrimaryButton(
            label: 'commit // start drill',
            icon: Icons.bolt,
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );
    expect(find.text('COMMIT // START DRILL'), findsOneWidget);
    await tester.tap(find.byType(TacticalPrimaryButton));
    expect(pressed, isTrue);
  });

  testWidgets('loading variant disables tap and shows spinner', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: TacticalPrimaryButton(
            label: 'arming',
            variant: TacticalButtonVariant.loading,
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(TacticalPrimaryButton));
    expect(pressed, isFalse);
  });
}
