import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atriarch/constants.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import 'package:atriarch/screens/shooter_picker_screen.dart';
import 'package:atriarch/state/shooter_state.dart';

/// In-memory fake ShooterRepository for widget tests.
/// Real sqflite + widget tests deadlock on macOS — avoid DatabaseHelper here.
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

Widget _host({
  required ShooterRepository repo,
  required ShooterState state,
  required Widget child,
}) =>
    MaterialApp(
      home: MultiProvider(
        providers: [
          Provider<ShooterRepository>.value(value: repo),
          ChangeNotifierProvider<ShooterState>.value(value: state),
        ],
        child: child,
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('lists existing shooters and Unassigned', (tester) async {
    final jeremy = Shooter(
      id: 'j',
      displayName: 'Jeremy',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final repo = _FakeShooterRepo([_unassigned(), jeremy]);
    final state = ShooterState(repo);
    await state.initialize();

    await tester.pumpWidget(_host(
      repo: repo,
      state: state,
      child: const ShooterPickerScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Jeremy'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.text('+ Add shooter'), findsOneWidget);
  });

  testWidgets('tapping a shooter selects it and pops', (tester) async {
    final jeremy = Shooter(
      id: 'j',
      displayName: 'Jeremy',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final repo = _FakeShooterRepo([_unassigned(), jeremy]);
    final state = ShooterState(repo);
    await state.initialize();

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => MultiProvider(
                      providers: [
                        Provider<ShooterRepository>.value(value: repo),
                        ChangeNotifierProvider<ShooterState>.value(value: state),
                      ],
                      child: const ShooterPickerScreen(),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        );
      }),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jeremy'));
    await tester.pumpAndSettle();

    expect(state.current!.id, 'j');
    expect(find.text('Open'), findsOneWidget);  // popped back
  });

  testWidgets('+ Add shooter opens form and creates shooter', (tester) async {
    final repo = _FakeShooterRepo([_unassigned()]);
    final state = ShooterState(repo);
    await state.initialize();

    await tester.pumpWidget(_host(
      repo: repo,
      state: state,
      child: const ShooterPickerScreen(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('+ Add shooter'));
    await tester.pumpAndSettle();

    expect(find.text('Add shooter'), findsOneWidget);  // form title
    expect(find.byType(TextField), findsWidgets);

    await tester.enterText(
      find.widgetWithText(TextField, 'Display name'),
      'New Shooter',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final all = await repo.listAll();
    expect(all.any((s) => s.displayName == 'New Shooter'), isTrue);
  });
}
