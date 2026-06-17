import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atriarch/widgets/target_setup/target_row.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders id, optional name, and online status', (tester) async {
    await tester.pumpWidget(_wrap(TargetRow(
      targetId: 3,
      displayName: 'Alpha',
      isOnline: true,
      currentGroup: null,
      groupOrder: const [],
      labels: const {},
      onSelectGroup: (_) {},
      onCreateNewGroup: () async => 1,
      onFlash: () {},
    )));
    expect(find.text('Target 3'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('shows online when online and no name', (tester) async {
    await tester.pumpWidget(_wrap(TargetRow(
      targetId: 3,
      displayName: null,
      isOnline: true,
      currentGroup: null,
      groupOrder: const [],
      labels: const {},
      onSelectGroup: (_) {},
      onCreateNewGroup: () async => 1,
      onFlash: () {},
    )));
    expect(find.text('online'), findsOneWidget);
  });

  testWidgets('shows offline when offline and no name', (tester) async {
    await tester.pumpWidget(_wrap(TargetRow(
      targetId: 3,
      displayName: null,
      isOnline: false,
      currentGroup: null,
      groupOrder: const [],
      labels: const {},
      onSelectGroup: (_) {},
      onCreateNewGroup: () async => 1,
      onFlash: () {},
    )));
    expect(find.text('offline'), findsOneWidget);
  });

  testWidgets('tapping flash fires callback when online', (tester) async {
    var flashed = 0;
    await tester.pumpWidget(_wrap(TargetRow(
      targetId: 3,
      displayName: null,
      isOnline: true,
      currentGroup: null,
      groupOrder: const [],
      labels: const {},
      onSelectGroup: (_) {},
      onCreateNewGroup: () async => 1,
      onFlash: () => flashed++,
    )));
    await tester.tap(find.byTooltip('Flash LED'));
    await tester.pumpAndSettle();
    expect(flashed, 1);
  });

  testWidgets('flash button is disabled when offline', (tester) async {
    var flashed = 0;
    await tester.pumpWidget(_wrap(TargetRow(
      targetId: 3,
      displayName: null,
      isOnline: false,
      currentGroup: null,
      groupOrder: const [],
      labels: const {},
      onSelectGroup: (_) {},
      onCreateNewGroup: () async => 1,
      onFlash: () => flashed++,
    )));
    final iconButton = tester.widgetList<IconButton>(find.byType(IconButton))
        .firstWhere((b) => b.tooltip == 'Flash LED');
    expect(iconButton.onPressed, isNull);
    expect(flashed, 0);
  });
}
