import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atriarch/widgets/target_setup/group_picker.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows "None" when assignment is null', (tester) async {
    await tester.pumpWidget(_wrap(GroupPicker(
      currentGroup: null,
      groupOrder: const [1, 2],
      labels: const {},
      onSelect: (_) {},
      onCreateNew: () async => 3,
    )));
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('shows label when assigned', (tester) async {
    await tester.pumpWidget(_wrap(GroupPicker(
      currentGroup: 1,
      groupOrder: const [1],
      labels: const {1: 'Left bank'},
      onSelect: (_) {},
      onCreateNew: () async => 2,
    )));
    expect(find.text('G1: Left bank'), findsOneWidget);
  });

  testWidgets('selecting a group calls onSelect', (tester) async {
    int? selected = -1;
    await tester.pumpWidget(_wrap(GroupPicker(
      currentGroup: null,
      groupOrder: const [1, 2],
      labels: const {},
      onSelect: (g) => selected = g,
      onCreateNew: () async => 3,
    )));
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('G2').last);
    await tester.pumpAndSettle();
    expect(selected, 2);
  });

  testWidgets('selecting None calls onSelect(null)', (tester) async {
    int? selected = 99;
    await tester.pumpWidget(_wrap(GroupPicker(
      currentGroup: 1,
      groupOrder: const [1],
      labels: const {},
      onSelect: (g) => selected = g,
      onCreateNew: () async => 2,
    )));
    await tester.tap(find.text('G1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None').last);
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });

  testWidgets('+ New group calls onCreateNew then onSelect', (tester) async {
    int? selected = -1;
    await tester.pumpWidget(_wrap(GroupPicker(
      currentGroup: null,
      groupOrder: const [1],
      labels: const {},
      onSelect: (g) => selected = g,
      onCreateNew: () async => 7,
    )));
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ New group…'));
    await tester.pumpAndSettle();
    expect(selected, 7);
  });
}
