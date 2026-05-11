import 'package:atriarch/models/target_unit.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/group_target_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Widget harness({
    required AppState state,
    required int groupIndex,
    required List<int> thisGroupIds,
    required List<int> assignedElsewhereIds,
    required Map<int, int> targetIdToGroupIndex,
    void Function(int targetId)? onAdd,
    void Function(int targetId)? onRemove,
    void Function(int targetId, int fromGroupIndex)? onMove,
  }) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: GroupTargetSheet(
            groupIndex: groupIndex,
            thisGroupIds: thisGroupIds,
            assignedElsewhereIds: assignedElsewhereIds,
            targetIdToGroupIndex: targetIdToGroupIndex,
            onAdd: onAdd ?? (_) {},
            onRemove: onRemove ?? (_) {},
            onMove: onMove ?? (_, __) {},
          ),
        ),
      ),
    );
  }

  testWidgets('header shows group label', (tester) async {
    final state = AppState();
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 3,
      thisGroupIds: const [],
      assignedElsewhereIds: const [],
      targetIdToGroupIndex: const {},
    ));
    expect(find.text('GROUP 04 — TARGETS'), findsOneWidget);
  });

  testWidgets('IN THIS GROUP section renders assigned targets with remove icon',
      (tester) async {
    final state = AppState()
      ..targets = [
        TargetUnit(id: 1, isOnline: true),
        TargetUnit(id: 2, isOnline: true),
      ];
    var removed = -1;
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [1, 2],
      assignedElsewhereIds: const [],
      targetIdToGroupIndex: const {},
      onRemove: (id) => removed = id,
    ));
    expect(find.text('IN THIS GROUP'), findsOneWidget);
    expect(find.text('T/U_01'), findsOneWidget);
    expect(find.text('T/U_02'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.close).first);
    expect(removed, 1);
  });

  testWidgets('AVAILABLE section renders unassigned online targets',
      (tester) async {
    final state = AppState()
      ..targets = [
        TargetUnit(id: 3, isOnline: true),
        TargetUnit(id: 4, isOnline: true),
      ];
    var added = -1;
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [],
      assignedElsewhereIds: const [],
      targetIdToGroupIndex: const {},
      onAdd: (id) => added = id,
    ));
    expect(find.text('AVAILABLE'), findsOneWidget);
    expect(find.text('T/U_03'), findsOneWidget);
    expect(find.text('T/U_04'), findsOneWidget);
    await tester.tap(find.text('T/U_03'));
    expect(added, 3);
  });

  testWidgets('ASSIGNED ELSEWHERE shows source-group badge and dispatches move',
      (tester) async {
    final state = AppState()
      ..targets = [TargetUnit(id: 5, isOnline: true)]
      ..setSkipMoveConfirmationForTesting(true);
    int? movedId;
    int? movedFrom;
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [],
      assignedElsewhereIds: const [5],
      targetIdToGroupIndex: const {5: 2}, // target 5 is in group index 2
      onMove: (id, from) {
        movedId = id;
        movedFrom = from;
      },
    ));
    expect(find.text('ASSIGNED ELSEWHERE'), findsOneWidget);
    expect(find.text('T/U_05'), findsOneWidget);
    expect(find.text('GROUP 03'), findsOneWidget);
    await tester.tap(find.text('T/U_05'));
    expect(movedId, 5);
    expect(movedFrom, 2);
  });

  testWidgets('empty sections are hidden and shows NO ONLINE TARGETS',
      (tester) async {
    final state = AppState();
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [],
      assignedElsewhereIds: const [],
      targetIdToGroupIndex: const {},
    ));
    expect(find.text('IN THIS GROUP'), findsNothing);
    expect(find.text('AVAILABLE'), findsNothing);
    expect(find.text('ASSIGNED ELSEWHERE'), findsNothing);
    expect(find.text('NO ONLINE TARGETS'), findsOneWidget);
  });

  testWidgets(
      'tapping ASSIGNED ELSEWHERE shows confirmation dialog when not skipped',
      (tester) async {
    final state = AppState()
      ..targets = [TargetUnit(id: 5, isOnline: true)]
      ..setSkipMoveConfirmationForTesting(false);
    int? movedId;
    int? movedFrom;
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [],
      assignedElsewhereIds: const [5],
      targetIdToGroupIndex: const {5: 2},
      onMove: (id, from) {
        movedId = id;
        movedFrom = from;
      },
    ));
    await tester.tap(find.text('T/U_05'));
    await tester.pumpAndSettle();
    expect(find.text('MOVE TARGET'), findsOneWidget);
    expect(find.textContaining('Move T/U_05 from GROUP 03 to GROUP 01?'),
        findsOneWidget);
    expect(movedId, isNull); // not yet dispatched
    await tester.tap(find.text('MOVE'));
    await tester.pumpAndSettle();
    expect(movedId, 5);
    expect(movedFrom, 2);
  });

  testWidgets('tapping CANCEL discards the move', (tester) async {
    final state = AppState()
      ..targets = [TargetUnit(id: 5, isOnline: true)]
      ..setSkipMoveConfirmationForTesting(false);
    int? movedId;
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [],
      assignedElsewhereIds: const [5],
      targetIdToGroupIndex: const {5: 2},
      onMove: (id, _) => movedId = id,
    ));
    await tester.tap(find.text('T/U_05'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(movedId, isNull);
  });

  testWidgets('dialog is skipped when skipMoveConfirmation is true',
      (tester) async {
    final state = AppState()
      ..targets = [TargetUnit(id: 5, isOnline: true)]
      ..setSkipMoveConfirmationForTesting(true);
    int? movedId;
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [],
      assignedElsewhereIds: const [5],
      targetIdToGroupIndex: const {5: 2},
      onMove: (id, _) => movedId = id,
    ));
    await tester.tap(find.text('T/U_05'));
    await tester.pumpAndSettle();
    expect(find.text('MOVE TARGET'), findsNothing);
    expect(movedId, 5);
  });

  testWidgets("checking \"Don't show this again\" persists the preference",
      (tester) async {
    final state = AppState()
      ..targets = [TargetUnit(id: 5, isOnline: true)]
      ..setSkipMoveConfirmationForTesting(false);
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [],
      assignedElsewhereIds: const [5],
      targetIdToGroupIndex: const {5: 2},
      onMove: (_, __) {},
    ));
    await tester.tap(find.text('T/U_05'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MOVE'));
    await tester.pumpAndSettle();
    expect(state.skipMoveConfirmation, true);
  });
}
