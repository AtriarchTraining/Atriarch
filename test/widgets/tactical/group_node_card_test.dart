import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/group_node_card.dart';

void main() {
  testWidgets('assigned renders check icon and ASSIGNED label',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: GroupNodeCard(
            groupIndex: 0,
            targetIds: const [1, 2, 3],
            selected: false,
            onTap: () {},
            onRemoveTarget: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('NODE_01'), findsOneWidget);
    expect(find.text('GROUP 01'), findsOneWidget);
    expect(find.text('ASSIGNED'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('standby renders STANDBY when empty', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: GroupNodeCard(
            groupIndex: 1,
            targetIds: const [],
            selected: false,
            onTap: () {},
            onRemoveTarget: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('NODE_02'), findsOneWidget);
    expect(find.text('STANDBY'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('fires onTap when tapped', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: GroupNodeCard(
            groupIndex: 0,
            targetIds: const [],
            selected: false,
            onTap: () => tapped++,
            onRemoveTarget: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(GroupNodeCard));
    expect(tapped, 1);
  });
}
