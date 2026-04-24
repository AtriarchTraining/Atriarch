import 'package:atriarch/models/target_unit.dart';
import 'package:atriarch/util/target_name_resolver.dart';
import 'package:atriarch/widgets/target_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Collects whatever callback the sheet fires, so tests can assert on it
/// without shared mutable state fiddling.
class _CallbackRecorder {
  int identifyCount = 0;
  int toggleNoShootCount = 0;
  int removeCount = 0;
  int restoreCount = 0;
  List<String?> renames = <String?>[];
}

TargetActionsSheet _buildSheet({
  required TargetUnit target,
  required _CallbackRecorder rec,
  Map<int, String> names = const <int, String>{},
  bool isRemoved = false,
}) {
  return TargetActionsSheet(
    target: target,
    resolver: TargetNameResolver(names),
    isRemoved: isRemoved,
    onIdentify: () => rec.identifyCount++,
    onRenameSaved: (name) => rec.renames.add(name),
    onToggleNoShoot: () => rec.toggleNoShootCount++,
    onRemoveConfirmed: () => rec.removeCount++,
    onRestoreConfirmed: () => rec.restoreCount++,
  );
}

/// Pumps a host app that opens the sheet in a modal bottom sheet, mirroring
/// how program_a_setup_screen invokes it.
Future<void> _pumpSheet(
  WidgetTester tester, {
  required TargetUnit target,
  required _CallbackRecorder rec,
  Map<int, String> names = const <int, String>{},
  bool isRemoved = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => _buildSheet(
                      target: target,
                      rec: rec,
                      names: names,
                      isRemoved: isRemoved,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('TargetActionsSheet', () {
    testWidgets('renders all four rows', (tester) async {
      final rec = _CallbackRecorder();
      final target = TargetUnit(id: 3, isOnline: true);
      await _pumpSheet(tester, target: target, rec: rec);

      expect(find.text('Identify (flash LED)'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Toggle No-Shoot (currently OFF)'), findsOneWidget);
      expect(find.text('Remove from fleet'), findsOneWidget);
    });

    testWidgets('No-Shoot label reflects target.isNoShoot', (tester) async {
      final rec = _CallbackRecorder();
      final target = TargetUnit(id: 3, isOnline: true, isNoShoot: true);
      await _pumpSheet(tester, target: target, rec: rec);
      expect(find.text('Toggle No-Shoot (currently ON)'), findsOneWidget);
    });

    testWidgets('Identify fires the callback and closes the sheet',
        (tester) async {
      final rec = _CallbackRecorder();
      final target = TargetUnit(id: 3, isOnline: true);
      await _pumpSheet(tester, target: target, rec: rec);
      await tester.tap(find.text('Identify (flash LED)'));
      await tester.pumpAndSettle();
      expect(rec.identifyCount, 1);
      expect(find.text('Identify (flash LED)'), findsNothing);
    });

    testWidgets('Toggle No-Shoot fires the callback and closes the sheet',
        (tester) async {
      final rec = _CallbackRecorder();
      final target = TargetUnit(id: 3, isOnline: true);
      await _pumpSheet(tester, target: target, rec: rec);
      await tester.tap(find.text('Toggle No-Shoot (currently OFF)'));
      await tester.pumpAndSettle();
      expect(rec.toggleNoShootCount, 1);
    });

    testWidgets('Rename dialog enforces 20-char maxLength', (tester) async {
      final rec = _CallbackRecorder();
      final target = TargetUnit(id: 3, isOnline: true);
      await _pumpSheet(tester, target: target, rec: rec);

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).maxLength, 20);
    });

    testWidgets('Rename save fires onRenameSaved with trimmed value',
        (tester) async {
      final rec = _CallbackRecorder();
      final target = TargetUnit(id: 3, isOnline: true);
      await _pumpSheet(tester, target: target, rec: rec);

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Flipper  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(rec.renames, ['Flipper']);
    });

    testWidgets('Rename save with empty text fires onRenameSaved(null)',
        (tester) async {
      final rec = _CallbackRecorder();
      final target = TargetUnit(id: 3, isOnline: true);
      await _pumpSheet(
        tester,
        target: target,
        rec: rec,
        names: {3: 'Flipper'},
      );

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(rec.renames, [null]);
    });

    testWidgets('Rename cancel does not fire onRenameSaved', (tester) async {
      final rec = _CallbackRecorder();
      final target = TargetUnit(id: 3, isOnline: true);
      await _pumpSheet(tester, target: target, rec: rec);

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'newname');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(rec.renames, isEmpty);
    });

    testWidgets('Remove confirmation: confirm fires onRemoveConfirmed',
        (tester) async {
      final rec = _CallbackRecorder();
      final target = TargetUnit(id: 3, isOnline: true);
      await _pumpSheet(tester, target: target, rec: rec);

      await tester.tap(find.text('Remove from fleet'));
      await tester.pumpAndSettle();
      // Match the confirm button in the AlertDialog, not the sheet row.
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(rec.removeCount, 1);
    });

    testWidgets('Remove confirmation: cancel does not fire onRemoveConfirmed',
        (tester) async {
      final rec = _CallbackRecorder();
      final target = TargetUnit(id: 3, isOnline: true);
      await _pumpSheet(tester, target: target, rec: rec);

      await tester.tap(find.text('Remove from fleet'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(rec.removeCount, 0);
    });

    testWidgets('isRemoved swaps the last row for Restore', (tester) async {
      final rec = _CallbackRecorder();
      final target = TargetUnit(id: 3, isOnline: true);
      await _pumpSheet(tester, target: target, rec: rec, isRemoved: true);

      expect(find.text('Restore to fleet'), findsOneWidget);
      expect(find.text('Remove from fleet'), findsNothing);

      await tester.tap(find.text('Restore to fleet'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Restore'));
      await tester.pumpAndSettle();

      expect(rec.restoreCount, 1);
    });

    testWidgets('header shows resolved display name', (tester) async {
      final rec = _CallbackRecorder();
      final target = TargetUnit(id: 3, isOnline: true);
      await _pumpSheet(
        tester,
        target: target,
        rec: rec,
        names: {3: 'Flipper'},
      );
      expect(find.text('Flipper'), findsOneWidget);
    });

    testWidgets('header shows T{id} when no custom name', (tester) async {
      final rec = _CallbackRecorder();
      final target = TargetUnit(id: 7, isOnline: true);
      await _pumpSheet(tester, target: target, rec: rec);
      expect(find.text('T7'), findsOneWidget);
    });
  });
}
