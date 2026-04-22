// In-memory fake ShooterRepository for widget tests.
// Real sqflite + widget tests deadlock on macOS — avoid DatabaseHelper here.
// Used by any widget test that mounts a screen depending on ShooterState.

import 'package:atriarch/constants.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/shooter_repository.dart';

class FakeShooterRepo implements ShooterRepository {
  final Map<String, Shooter> _byId;
  FakeShooterRepo(List<Shooter> initial)
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

Shooter makeUnassignedShooter() => Shooter(
      id: kUnassignedShooterId,
      displayName: kUnassignedShooterName,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
