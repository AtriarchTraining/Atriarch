import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import 'package:atriarch/state/shooter_state.dart';
import 'package:atriarch/widgets/shooter_chip.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() => initializeTestDatabase());

  testWidgets('renders current shooter name', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = await DatabaseHelper.openForTesting();
    final repo = ShooterRepository(db);
    await repo.insert(Shooter(
      id: 'j',
      displayName: 'Jeremy',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    ));
    final state = ShooterState(repo);
    await state.initialize();
    await state.selectShooter('j');

    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(
        value: state,
        child: Scaffold(
          appBar: AppBar(
            actions: [ShooterChip(onTap: () => tapped = true)],
          ),
        ),
      ),
    ));

    expect(find.text('Firing as: Jeremy'), findsOneWidget);

    await tester.tap(find.byType(ShooterChip));
    await tester.pump();
    expect(tapped, isTrue);

    await db.close();
  });

  testWidgets('renders Unassigned state when no shooter selected', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = await DatabaseHelper.openForTesting();
    final state = ShooterState(ShooterRepository(db));
    await state.initialize();  // defaults to Unassigned

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(
        value: state,
        child: Scaffold(
          appBar: AppBar(actions: [ShooterChip(onTap: () {})]),
        ),
      ),
    ));

    expect(find.text('Firing as: Unassigned'), findsOneWidget);
    await db.close();
  });
}
