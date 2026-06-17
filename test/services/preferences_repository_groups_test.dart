import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:atriarch/services/preferences_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<PreferencesRepository> _repo() async =>
      PreferencesRepository(await SharedPreferences.getInstance());

  group('target group assignments', () {
    test('empty by default', () async {
      final repo = await _repo();
      expect(await repo.getTargetGroups(), isEmpty);
    });

    test('set + read round-trip', () async {
      final repo = await _repo();
      await repo.setTargetGroup(3, 1);
      await repo.setTargetGroup(5, 2);
      expect(await repo.getTargetGroups(), {3: 1, 5: 2});
    });

    test('passing null group unassigns', () async {
      final repo = await _repo();
      await repo.setTargetGroup(3, 1);
      await repo.setTargetGroup(3, null);
      expect(await repo.getTargetGroups(), isEmpty);
    });
  });

  group('target group labels', () {
    test('empty by default', () async {
      final repo = await _repo();
      expect(await repo.getTargetGroupLabels(), isEmpty);
    });

    test('set + read round-trip', () async {
      final repo = await _repo();
      await repo.setTargetGroupLabel(1, 'Left bank');
      expect(await repo.getTargetGroupLabels(), {1: 'Left bank'});
    });

    test('null label removes entry', () async {
      final repo = await _repo();
      await repo.setTargetGroupLabel(1, 'Left bank');
      await repo.setTargetGroupLabel(1, null);
      expect(await repo.getTargetGroupLabels(), isEmpty);
    });
  });

  group('target group order', () {
    test('empty by default', () async {
      final repo = await _repo();
      expect(await repo.getTargetGroupOrder(), isEmpty);
    });

    test('round-trip preserves order', () async {
      final repo = await _repo();
      await repo.setTargetGroupOrder([3, 1, 2]);
      expect(await repo.getTargetGroupOrder(), [3, 1, 2]);
    });

    test('empty list clears key', () async {
      final repo = await _repo();
      await repo.setTargetGroupOrder([1, 2]);
      await repo.setTargetGroupOrder(<int>[]);
      expect(await repo.getTargetGroupOrder(), isEmpty);
    });
  });
}
