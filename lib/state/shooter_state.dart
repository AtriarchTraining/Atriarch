import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../models/shooter.dart';
import '../repositories/shooter_repository.dart';

class ShooterState extends ChangeNotifier {
  final ShooterRepository _repo;
  Shooter? _current;

  ShooterState(this._repo);

  Shooter? get current => _current;

  /// Load last-selected shooter from prefs, or fall back to Unassigned.
  /// Call once after DB is open.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(kPrefsLastShooterIdKey);
    if (savedId != null) {
      final saved = await _repo.getById(savedId);
      if (saved != null) {
        _current = saved;
        notifyListeners();
        return;
      }
      // Saved id no longer exists — fall through to Unassigned.
      await prefs.remove(kPrefsLastShooterIdKey);
    }
    _current = await _repo.getById(kUnassignedShooterId);
    notifyListeners();
  }

  Future<void> selectShooter(String id) async {
    final s = await _repo.getById(id);
    if (s == null) {
      throw StateError('No shooter with id $id');
    }
    _current = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefsLastShooterIdKey, id);
    notifyListeners();
  }

  /// Refresh the cached current shooter (e.g., after editing name/email).
  Future<void> refresh() async {
    final id = _current?.id;
    if (id == null) return;
    _current = await _repo.getById(id);
    notifyListeners();
  }
}
