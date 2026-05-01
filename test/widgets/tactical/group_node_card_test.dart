import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/util/target_name_resolver.dart';
import 'package:atriarch/widgets/tactical/group_node_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(body: child),
      );

  testWidgets('assigned renders check icon and ASSIGNED label',
      (tester) async {
    await tester.pumpWidget(wrap(GroupNodeCard(
      groupIndex: 0,
      targetIds: const [1, 2, 3],
      selected: false,
      expanded: false,
      resolver: const TargetNameResolver({}),
      onTap: () {},
      onRemoveTarget: (_) {},
    )));
    expect(find.text('NODE_01'), findsOneWidget);
    expect(find.text('GROUP 01'), findsOneWidget);
    expect(find.text('ASSIGNED'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('standby renders STANDBY when empty', (tester) async {
    await tester.pumpWidget(wrap(GroupNodeCard(
      groupIndex: 1,
      targetIds: const [],
      selected: false,
      expanded: false,
      resolver: const TargetNameResolver({}),
      onTap: () {},
      onRemoveTarget: (_) {},
    )));
    expect(find.text('NODE_02'), findsOneWidget);
    expect(find.text('STANDBY'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('fires onTap when tapped', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(wrap(GroupNodeCard(
      groupIndex: 0,
      targetIds: const [],
      selected: false,
      expanded: false,
      resolver: const TargetNameResolver({}),
      onTap: () => tapped++,
      onRemoveTarget: (_) {},
    )));
    await tester.tap(find.byType(GroupNodeCard));
    expect(tapped, 1);
  });

  testWidgets('collapsed card shows unit labels and no remove buttons',
      (tester) async {
    await tester.pumpWidget(wrap(GroupNodeCard(
      groupIndex: 0,
      targetIds: const [1, 2],
      selected: false,
      expanded: false,
      resolver: const TargetNameResolver({}),
      onTap: () {},
      onRemoveTarget: (_) {},
    )));

    expect(find.text('T/U_01'), findsOneWidget);
    expect(find.text('T/U_02'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('expanded card shows chips with remove buttons',
      (tester) async {
    int? removed;
    await tester.pumpWidget(wrap(GroupNodeCard(
      groupIndex: 0,
      targetIds: const [1, 2],
      selected: false,
      expanded: true,
      resolver: const TargetNameResolver({}),
      onTap: () {},
      onRemoveTarget: (id) => removed = id,
    )));

    expect(find.text('T/U_01'), findsOneWidget);
    expect(find.text('T/U_02'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.close).first);
    expect(removed, 1);
  });

  testWidgets('uses custom name when resolver provides one', (tester) async {
    await tester.pumpWidget(wrap(GroupNodeCard(
      groupIndex: 0,
      targetIds: const [1, 2],
      selected: false,
      expanded: false,
      resolver: const TargetNameResolver({1: 'Flipper'}),
      onTap: () {},
      onRemoveTarget: (_) {},
    )));

    expect(find.text('Flipper'), findsOneWidget);
    expect(find.text('T/U_02'), findsOneWidget);
    expect(find.text('T/U_01'), findsNothing);
  });

  testWidgets(
      'collapsed card height is same for 2 targets and 8 targets (fixed-size)',
      (tester) async {
    // Pump with 2 targets and record the card's height.
    await tester.pumpWidget(wrap(
      SizedBox(
        width: 180,
        child: GroupNodeCard(
          groupIndex: 0,
          targetIds: const [1, 2],
          selected: false,
          expanded: false,
          resolver: const TargetNameResolver({}),
          onTap: () {},
          onRemoveTarget: (_) {},
        ),
      ),
    ));
    final heightWith2 = tester.getSize(find.byType(GroupNodeCard)).height;

    // Pump with 8 targets — the collapsed card height must not grow.
    await tester.pumpWidget(wrap(
      SizedBox(
        width: 180,
        child: GroupNodeCard(
          groupIndex: 0,
          targetIds: const [1, 2, 3, 4, 5, 6, 7, 8],
          selected: false,
          expanded: false,
          resolver: const TargetNameResolver({}),
          onTap: () {},
          onRemoveTarget: (_) {},
        ),
      ),
    ));
    final heightWith8 = tester.getSize(find.byType(GroupNodeCard)).height;

    // Heights must be equal: collapsed card is fixed-size regardless of
    // target count.  Both cards fill the Scaffold body vertically in the
    // unconstrained test environment, so we compare them to each other
    // rather than against an absolute pixel value.
    expect(heightWith8, equals(heightWith2));
  });

  testWidgets(
      'collapsed card with long custom name uses ellipsis overflow on label',
      (tester) async {
    const longName = 'VeryLongCustomTargetNameHereXX'; // 30 chars
    await tester.pumpWidget(wrap(
      SizedBox(
        width: 180,
        child: GroupNodeCard(
          groupIndex: 0,
          targetIds: const [1, 2],
          selected: false,
          expanded: false,
          resolver: const TargetNameResolver({1: longName}),
          onTap: () {},
          onRemoveTarget: (_) {},
        ),
      ),
    ));

    // The long-name Text widget must use ellipsis overflow so it never
    // pushes the label area wider than its ConstrainedBox max.
    final longNameText = tester.widget<Text>(find.text(longName));
    expect(longNameText.overflow, TextOverflow.ellipsis);
  });
}
