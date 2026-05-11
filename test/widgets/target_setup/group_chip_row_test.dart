import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atriarch/widgets/target_setup/group_chip_row.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders one chip per group in order', (tester) async {
    await tester.pumpWidget(_wrap(GroupChipRow(
      groupOrder: const [1, 3, 2],
      labels: const {1: 'Left bank'},
      onAddGroup: () {},
      onRenameGroup: (_) {},
      onDeleteGroup: (_) {},
    )));
    expect(find.text('G1: Left bank'), findsOneWidget);
    expect(find.text('G3'), findsOneWidget);
    expect(find.text('G2'), findsOneWidget);
    expect(find.text('+ Add group'), findsOneWidget);
  });

  testWidgets('tapping + Add group fires callback', (tester) async {
    var added = 0;
    await tester.pumpWidget(_wrap(GroupChipRow(
      groupOrder: const [],
      labels: const {},
      onAddGroup: () => added++,
      onRenameGroup: (_) {},
      onDeleteGroup: (_) {},
    )));
    await tester.tap(find.text('+ Add group'));
    await tester.pumpAndSettle();
    expect(added, 1);
  });

  testWidgets('tapping a group chip fires rename callback with group number',
      (tester) async {
    int? renamed;
    await tester.pumpWidget(_wrap(GroupChipRow(
      groupOrder: const [1, 2],
      labels: const {},
      onAddGroup: () {},
      onRenameGroup: (g) => renamed = g,
      onDeleteGroup: (_) {},
    )));
    await tester.tap(find.text('G2'));
    await tester.pumpAndSettle();
    expect(renamed, 2);
  });
}
