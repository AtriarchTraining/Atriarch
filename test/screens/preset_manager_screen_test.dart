// test/screens/preset_manager_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/drill_template.dart';
import 'package:atriarch/repositories/drill_template_repository.dart';
import 'package:atriarch/screens/preset_manager_screen.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import '../test_helpers/fake_drill_template_repository.dart';

DrillTemplate _makeTemplate({
  String id = 'id-1',
  String name = 'Alpha Preset',
  ProgramType programType = ProgramType.programA,
}) {
  final config = DrillConfig(
    programType: programType,
    startMin: 1.0,
    startMax: 3.0,
    iterations: 5,
  );
  return DrillTemplate(
    id: id,
    shooterId: null,
    name: name,
    programType: programType,
    config: config,
    configHash: 'hash-$id',
    createdAt: DateTime(2026, 1, 1),
  );
}

Widget _buildApp(FakeDrillTemplateRepository repo) {
  return MultiProvider(
    providers: [
      Provider<DrillTemplateRepository>.value(value: repo),
      ChangeNotifierProvider<AppState>(create: (_) => AppState()),
    ],
    child: MaterialApp(
      theme: buildAtriarchDarkTheme(),
      home: const PresetManagerScreen(),
    ),
  );
}

void main() {
  testWidgets('empty state shows NO PRESETS SAVED.', (tester) async {
    final repo = FakeDrillTemplateRepository();
    await tester.pumpWidget(_buildApp(repo));
    await tester.pump();
    expect(find.text('NO PRESETS SAVED.'), findsOneWidget);
  });

  testWidgets('renders template list with 2 seeded templates', (tester) async {
    final repo = FakeDrillTemplateRepository();
    await repo.insert(_makeTemplate(id: 'id-1', name: 'Alpha Preset'));
    await repo.insert(_makeTemplate(id: 'id-2', name: 'Bravo Preset'));

    await tester.pumpWidget(_buildApp(repo));
    await tester.pump();

    expect(find.text('Alpha Preset'), findsOneWidget);
    expect(find.text('Bravo Preset'), findsOneWidget);
  });

  testWidgets('delete flow: swipe reveals DEL, tap DEL, confirm removes row',
      (tester) async {
    final repo = FakeDrillTemplateRepository();
    await repo.insert(_makeTemplate(id: 'id-1', name: 'Delete Me'));

    await tester.pumpWidget(_buildApp(repo));
    await tester.pump();

    // Verify row is present.
    expect(find.text('Delete Me'), findsOneWidget);

    // Swipe left to reveal actions.
    await tester.drag(find.text('Delete Me'), const Offset(-200, 0));
    await tester.pumpAndSettle();

    // Tap DEL tile.
    expect(find.text('DEL'), findsOneWidget);
    await tester.tap(find.text('DEL'));
    await tester.pumpAndSettle();

    // Confirm deletion in the dialog.
    expect(find.text('DELETE'), findsOneWidget);
    await tester.tap(find.text('DELETE'));
    await tester.pumpAndSettle();

    // Row should be gone, empty state shown.
    expect(find.text('Delete Me'), findsNothing);
    expect(find.text('NO PRESETS SAVED.'), findsOneWidget);
  });

  testWidgets('rename flow: swipe reveals REN, tap REN, enter name, confirm updates row',
      (tester) async {
    final repo = FakeDrillTemplateRepository();
    await repo.insert(_makeTemplate(id: 'id-1', name: 'Old Name'));

    await tester.pumpWidget(_buildApp(repo));
    await tester.pump();

    // Verify row is present.
    expect(find.text('Old Name'), findsOneWidget);

    // Swipe left to reveal actions.
    await tester.drag(find.text('Old Name'), const Offset(-200, 0));
    await tester.pumpAndSettle();

    // Tap REN tile.
    expect(find.text('REN'), findsOneWidget);
    await tester.tap(find.text('REN'));
    await tester.pumpAndSettle();

    // Clear the text field and enter a new name.
    final nameField = find.byType(TextField);
    await tester.tap(nameField);
    await tester.pump();
    await tester.enterText(nameField, 'New Name');
    await tester.pump();

    // Confirm rename.
    await tester.tap(find.text('RENAME'));
    await tester.pumpAndSettle();

    // Row should show updated name.
    expect(find.text('New Name'), findsOneWidget);
    expect(find.text('Old Name'), findsNothing);
  });
}
