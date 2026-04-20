import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/models/target_unit.dart';
import 'package:atriarch/widgets/tactical/target_node_chip.dart';

void main() {
  testWidgets('renders T## and fires onTap', (tester) async {
    var tapped = false;
    final target = TargetUnit(id: 3, isOnline: true, isNoShoot: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: TargetNodeChip(
            target: target,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    expect(find.text('T3'), findsOneWidget);
    await tester.tap(find.byType(TargetNodeChip));
    expect(tapped, isTrue);
  });
}
