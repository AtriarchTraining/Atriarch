import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:atriarch/services/preferences_repository.dart';
import 'package:atriarch/state/app_state.dart';

import '../helpers/fake_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AppState> _state() async {
    final prefs = PreferencesRepository(await SharedPreferences.getInstance());
    final s = AppState.forTesting(
      sessions: FakeSessionRepository(),
      shooterState: FakeShooterState(),
      preferences: prefs,
    );
    await s.hydratePreferences();
    return s;
  }

  group('group APIs', () {
    test('createTargetGroup returns 1 on empty state', () async {
      final s = await _state();
      final g = await s.createTargetGroup();
      expect(g, 1);
      expect(s.targetGroupOrder, [1]);
    });

    test('createTargetGroup returns max+1 even across deletes', () async {
      final s = await _state();
      await s.createTargetGroup(); // 1
      await s.createTargetGroup(); // 2
      await s.deleteTargetGroup(2);
      final g = await s.createTargetGroup();
      expect(g, 3);
      expect(s.targetGroupOrder, [1, 3]);
    });

    test('setTargetGroup persists assignment and notifies', () async {
      final s = await _state();
      var notified = false;
      s.addListener(() => notified = true);
      await s.createTargetGroup();
      await s.setTargetGroup(7, 1);
      expect(s.targetGroupAssignments, {7: 1});
      expect(notified, isTrue);
    });

    test('renameTargetGroup stores label', () async {
      final s = await _state();
      await s.createTargetGroup();
      await s.renameTargetGroup(1, 'Left bank');
      expect(s.targetGroupLabels[1], 'Left bank');
    });

    test('deleteTargetGroup unassigns members and removes from order', () async {
      final s = await _state();
      await s.createTargetGroup(); // 1
      await s.setTargetGroup(7, 1);
      await s.renameTargetGroup(1, 'Left bank');
      await s.deleteTargetGroup(1);
      expect(s.targetGroupAssignments, isEmpty);
      expect(s.targetGroupLabels, isEmpty);
      expect(s.targetGroupOrder, isEmpty);
    });
  });

  group('buildSeededGroups', () {
    test('empty state -> empty list', () async {
      final s = await _state();
      expect(s.buildSeededGroups(), isEmpty);
    });

    test('omits empty persistent groups', () async {
      final s = await _state();
      await s.createTargetGroup(); // 1
      await s.createTargetGroup(); // 2
      await s.setTargetGroup(7, 1);
      final groups = s.buildSeededGroups();
      expect(groups, hasLength(1));
      expect(groups.single.targetIds, [7]);
    });

    test('emits in targetGroupOrder', () async {
      final s = await _state();
      await s.createTargetGroup(); // 1
      await s.createTargetGroup(); // 2
      await s.setTargetGroup(7, 2);
      await s.setTargetGroup(8, 1);
      final groups = s.buildSeededGroups();
      expect(groups.map((g) => g.targetIds).toList(), [[8], [7]]);
    });

    test('uses custom label when present', () async {
      final s = await _state();
      await s.createTargetGroup();
      await s.renameTargetGroup(1, 'Left bank');
      await s.setTargetGroup(7, 1);
      final groups = s.buildSeededGroups();
      expect(groups.single.name, 'Left bank');
    });
  });

  group('hydratePreferences', () {
    test('loads existing group state', () async {
      SharedPreferences.setMockInitialValues({
        'target_groups': '{"7":1,"8":2}',
        'target_group_labels': '{"1":"Left bank"}',
        'target_group_order': '1,2',
      });
      final s = await _state();
      expect(s.targetGroupAssignments, {7: 1, 8: 2});
      expect(s.targetGroupLabels, {1: 'Left bank'});
      expect(s.targetGroupOrder, [1, 2]);
    });
  });
}
