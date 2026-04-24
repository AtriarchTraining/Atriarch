import 'package:atriarch/models/drill_template.dart';
import 'package:atriarch/repositories/drill_template_repository.dart';

/// In-memory fake for widget tests that need DrillTemplateRepository without
/// touching sqflite (which deadlocks in widget-test harness on macOS).
class FakeDrillTemplateRepository implements DrillTemplateRepository {
  final Map<String, DrillTemplate> _byId = {};

  @override
  Future<void> insert(DrillTemplate t) async {
    if (_byId.containsKey(t.id)) {
      throw StateError('Template id ${t.id} already exists');
    }
    _byId[t.id] = t;
  }

  @override
  Future<void> upsert(DrillTemplate t) async => _byId[t.id] = t;

  @override
  Future<DrillTemplate?> getById(String id) async => _byId[id];

  @override
  Future<List<DrillTemplate>> listAll() async {
    final list = _byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Future<void> delete(String id) async => _byId.remove(id);
}
