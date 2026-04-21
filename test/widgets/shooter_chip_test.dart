import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atriarch/constants.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import 'package:atriarch/state/shooter_state.dart';
import 'package:atriarch/widgets/shooter_chip.dart';

/// In-memory fake that matches ShooterRepository's public API without
/// touching SQLite. Widget tests don't need a real DB — they just need
/// ShooterState to have a `current` value.
class _FakeShooterRepo implements ShooterRepository {
  final Map<String, Shooter> _byId;
  _FakeShooterRepo(List<Shooter> initial)
      : _byId = {for (final s in initial) s.id: s};

  @override
  Future<Shooter?> getById(String id) async => _byId[id];

  @override
  Future<void> insert(Shooter s) async => _byId[s.id] = s;

  @override
  Future<void> update(Shooter s) async => _byId[s.id] = s;

  @override
  Future<void> delete(String id) async {
    if (id == kUnassignedShooterId) {
      throw StateError('Cannot delete reserved Unassigned shooter');
    }
    _byId.remove(id);
  }

  @override
  Future<List<Shooter>> listAll() async {
    final all = _byId.values.toList();
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }
}

Shooter _unassigned() => Shooter(
      id: kUnassignedShooterId,
      displayName: 'Unassigned',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders current shooter name', (tester) async {
    final jeremy = Shooter(
      id: 'j',
      displayName: 'Jeremy',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final repo = _FakeShooterRepo([_unassigned(), jeremy]);
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
  });

  testWidgets('renders Unassigned state when no shooter selected', (tester) async {
    final repo = _FakeShooterRepo([_unassigned()]);
    final state = ShooterState(repo);
    await state.initialize(); // defaults to Unassigned

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(
        value: state,
        child: Scaffold(
          appBar: AppBar(actions: [ShooterChip(onTap: () {})]),
        ),
      ),
    ));

    expect(find.text('Firing as: Unassigned'), findsOneWidget);
  });
}
