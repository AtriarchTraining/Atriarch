import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/constants.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() => initializeTestDatabase());

  group('ShooterRepository', () {
    late Database db;
    late ShooterRepository repo;

    setUp(() async {
      db = await DatabaseHelper.openForTesting();
      repo = ShooterRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('listAll returns the seeded Unassigned shooter after init', () async {
      final all = await repo.listAll();
      expect(all.map((s) => s.id), contains(kUnassignedShooterId));
    });

    test('insert and getById round-trip', () async {
      final s = Shooter(
        id: 'uuid-jeremy',
        displayName: 'Jeremy',
        contactEmail: 'j@example.com',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      await repo.insert(s);
      final back = await repo.getById('uuid-jeremy');
      expect(back, s);
    });

    test('getById returns null for unknown id', () async {
      expect(await repo.getById('nope'), isNull);
    });

    test('update modifies display_name and keeps id stable', () async {
      final s = Shooter(
        id: 'uuid-a',
        displayName: 'Old',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      await repo.insert(s);
      await repo.update(s.copyWith(displayName: 'New'));
      expect((await repo.getById('uuid-a'))!.displayName, 'New');
    });

    test('delete removes the row and cascades to sessions (empty cascade)', () async {
      final s = Shooter(
        id: 'uuid-del',
        displayName: 'Del',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      await repo.insert(s);
      await repo.delete('uuid-del');
      expect(await repo.getById('uuid-del'), isNull);
    });

    test('cannot delete the Unassigned reserved shooter', () async {
      expect(
        () => repo.delete(kUnassignedShooterId),
        throwsA(isA<StateError>()),
      );
    });

    test('listAll orders by created_at DESC', () async {
      await repo.insert(Shooter(
        id: 'old',
        displayName: 'Old',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
      await repo.insert(Shooter(
        id: 'new',
        displayName: 'New',
        createdAt: DateTime.fromMillisecondsSinceEpoch(5000),
      ));
      final ids = (await repo.listAll()).map((s) => s.id).toList();
      // Unassigned was seeded with now() in onCreate, which is > 5000, so it
      // lands first. Filter it out for the ordering assertion.
      final nonReserved = ids.where((id) => id != kUnassignedShooterId).toList();
      expect(nonReserved, ['new', 'old']);
    });
  });
}
