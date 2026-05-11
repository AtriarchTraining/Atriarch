# Target Setup Screen Pass — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Target Setup screen stub with a real per-target list (status, group chip, flash button) backed by persistent groups that seed drill-time grouping.

**Architecture:** Persistent group assignments + labels + display order live in `SharedPreferences` (sibling to existing `target_names`). `AppState` exposes group APIs and a shared `walkTheRange()` routine. The setup screen renders three sections — header, groups chip row, target list — via new widgets in `lib/widgets/target_setup/`. `ProgramASetupScreen` seeds its initial `DrillConfig.groups` from `AppState.buildSeededGroups()` when not loading a saved template. The dead `TargetUnit.groupId` field is removed.

**Tech Stack:** Flutter, Provider, shared_preferences, flutter_test. Existing widget-test policy: fake repositories (no FFI sqflite — see memory `feedback_widget_tests_no_ffi_sqflite.md`).

**Spec:** [docs/superpowers/specs/2026-05-11-target-setup-screen-design.md](../specs/2026-05-11-target-setup-screen-design.md)

---

## Task 1: PreferencesRepository persistent-group storage

**Files:**
- Modify: `lib/services/preferences_repository.dart`
- Test: `test/services/preferences_repository_groups_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/services/preferences_repository_groups_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/preferences_repository_groups_test.dart`
Expected: FAIL — methods `getTargetGroups`, `setTargetGroup`, `getTargetGroupLabels`, `setTargetGroupLabel`, `getTargetGroupOrder`, `setTargetGroupOrder` not defined.

- [ ] **Step 3: Add storage methods to `PreferencesRepository`**

Edit `lib/services/preferences_repository.dart`. Add the three key constants near the top of the class alongside the existing ones:

```dart
  static const String _kTargetGroups = 'target_groups';
  static const String _kTargetGroupLabels = 'target_group_labels';
  static const String _kTargetGroupOrder = 'target_group_order';
```

Add these methods to the class (place them after `setRemovedTargetIds`):

```dart
  // --- target groups (Map<int targetId, int groupNumber>) ---
  Future<Map<int, int>> getTargetGroups() async {
    final raw = _prefs.getString(_kTargetGroups);
    if (raw == null || raw.isEmpty) return <int, int>{};
    final decoded = json.decode(raw);
    if (decoded is! Map) return <int, int>{};
    final result = <int, int>{};
    decoded.forEach((k, v) {
      final id = k is int ? k : int.tryParse('$k') ?? -1;
      final g = v is int ? v : int.tryParse('$v') ?? -1;
      if (id >= 0 && g >= 1) result[id] = g;
    });
    return result;
  }

  Future<void> setTargetGroup(int targetId, int? groupNumber) async {
    final current = Map<String, int>.from(
      (json.decode(_prefs.getString(_kTargetGroups) ?? '{}') as Map)
          .map((k, v) => MapEntry('$k', (v is num) ? v.toInt() : 0)),
    )..removeWhere((_, v) => v <= 0);
    final key = targetId.toString();
    if (groupNumber == null) {
      current.remove(key);
    } else {
      current[key] = groupNumber;
    }
    if (current.isEmpty) {
      await _prefs.remove(_kTargetGroups);
    } else {
      await _prefs.setString(_kTargetGroups, json.encode(current));
    }
  }

  // --- target group labels (Map<int groupNumber, String label>) ---
  Future<Map<int, String>> getTargetGroupLabels() async {
    final raw = _prefs.getString(_kTargetGroupLabels);
    if (raw == null || raw.isEmpty) return <int, String>{};
    final decoded = json.decode(raw);
    if (decoded is! Map) return <int, String>{};
    final result = <int, String>{};
    decoded.forEach((k, v) {
      final g = k is int ? k : int.tryParse('$k') ?? -1;
      if (g >= 1) result[g] = '$v';
    });
    return result;
  }

  Future<void> setTargetGroupLabel(int groupNumber, String? label) async {
    final current = Map<String, String>.from(
      (json.decode(_prefs.getString(_kTargetGroupLabels) ?? '{}') as Map)
          .map((k, v) => MapEntry('$k', '$v')),
    );
    final key = groupNumber.toString();
    if (label == null || label.isEmpty) {
      current.remove(key);
    } else {
      current[key] = label;
    }
    if (current.isEmpty) {
      await _prefs.remove(_kTargetGroupLabels);
    } else {
      await _prefs.setString(_kTargetGroupLabels, json.encode(current));
    }
  }

  // --- target group display order (List<int>) ---
  Future<List<int>> getTargetGroupOrder() async {
    final raw = _prefs.getString(_kTargetGroupOrder);
    if (raw == null || raw.isEmpty) return <int>[];
    return raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .where((g) => g >= 1)
        .toList();
  }

  Future<void> setTargetGroupOrder(List<int> order) async {
    if (order.isEmpty) {
      await _prefs.remove(_kTargetGroupOrder);
    } else {
      await _prefs.setString(_kTargetGroupOrder, order.join(','));
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/preferences_repository_groups_test.dart`
Expected: PASS — all tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/services/preferences_repository.dart test/services/preferences_repository_groups_test.dart
git commit -m "feat(prefs): persistent target group storage"
```

---

## Task 2: AppState group APIs + walkTheRange

**Files:**
- Modify: `lib/state/app_state.dart`
- Test: `test/state/app_state_groups_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/state/app_state_groups_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:atriarch/models/target_unit.dart';
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
```

If `test/helpers/fake_repositories.dart` does not yet expose `FakeSessionRepository` and `FakeShooterState`, search existing widget tests for the pattern and reuse the same fakes:

```bash
grep -rn "FakeSessionRepository\|FakeShooterState" test/ | head
```

If they exist elsewhere, change the import to point at the existing file. If neither pattern exists, create minimal fakes in `test/helpers/fake_repositories.dart`:

```dart
import 'package:atriarch/repositories/session_repository.dart';
import 'package:atriarch/state/shooter_state.dart';

class FakeSessionRepository implements SessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeShooterState implements ShooterState {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state/app_state_groups_test.dart`
Expected: FAIL — APIs not yet defined.

- [ ] **Step 3: Add private state + getters to `AppState`**

Edit `lib/state/app_state.dart`. Add these private fields next to `_targetNames`:

```dart
  Map<int, int> _targetGroupAssignments = <int, int>{};
  Map<int, String> _targetGroupLabels = <int, String>{};
  List<int> _targetGroupOrder = <int>[];
```

Add the corresponding public getters next to `targetNames`:

```dart
  Map<int, int> get targetGroupAssignments =>
      Map.unmodifiable(_targetGroupAssignments);
  Map<int, String> get targetGroupLabels =>
      Map.unmodifiable(_targetGroupLabels);
  List<int> get targetGroupOrder => List.unmodifiable(_targetGroupOrder);
```

- [ ] **Step 4: Hydrate group state in `hydratePreferences`**

In `hydratePreferences()` (currently at lines ~182-192), add three lines before the final `notifyListeners()`:

```dart
    _targetGroupAssignments = await prefs.getTargetGroups();
    _targetGroupLabels = await prefs.getTargetGroupLabels();
    _targetGroupOrder = await prefs.getTargetGroupOrder();
```

- [ ] **Step 5: Add the import for TargetGroup**

At the top of `lib/state/app_state.dart`, add to the imports:

```dart
import '../models/target_group.dart';
```

- [ ] **Step 6: Add the group mutation + seeding + walk APIs**

Insert after the existing `setTargetName` method:

```dart
  // --- Persistent target groups ---

  Future<int> createTargetGroup({String? label}) async {
    final next = _targetGroupOrder.isEmpty
        ? 1
        : (_targetGroupOrder.reduce((a, b) => a > b ? a : b) + 1);
    _targetGroupOrder = [..._targetGroupOrder, next];
    await preferences?.setTargetGroupOrder(_targetGroupOrder);
    if (label != null && label.isNotEmpty) {
      _targetGroupLabels[next] = label;
      await preferences?.setTargetGroupLabel(next, label);
    }
    notifyListeners();
    return next;
  }

  Future<void> renameTargetGroup(int groupNumber, String? label) async {
    if (label == null || label.isEmpty) {
      _targetGroupLabels.remove(groupNumber);
    } else {
      _targetGroupLabels[groupNumber] = label;
    }
    await preferences?.setTargetGroupLabel(groupNumber, label);
    notifyListeners();
  }

  Future<void> deleteTargetGroup(int groupNumber) async {
    _targetGroupOrder = _targetGroupOrder
        .where((g) => g != groupNumber)
        .toList(growable: false);
    _targetGroupLabels.remove(groupNumber);
    _targetGroupAssignments
        .removeWhere((_, g) => g == groupNumber);
    await preferences?.setTargetGroupOrder(_targetGroupOrder);
    await preferences?.setTargetGroupLabel(groupNumber, null);
    // Rewrite all assignments since multiple keys may have been removed.
    final remaining = Map<int, int>.from(_targetGroupAssignments);
    // Clear stored map by writing each removed id with null... but
    // simpler: write the remaining set by iterating both old + new.
    // We need to drop only entries pointing at groupNumber from prefs.
    // Re-read current stored map and rewrite individually:
    final stored = await preferences?.getTargetGroups() ?? <int, int>{};
    for (final id in stored.keys.toList()) {
      if (stored[id] == groupNumber) {
        await preferences?.setTargetGroup(id, null);
      }
    }
    // Sanity: in-memory must match remaining.
    _targetGroupAssignments = remaining;
    notifyListeners();
  }

  Future<void> setTargetGroup(int targetId, int? groupNumber) async {
    if (groupNumber == null) {
      _targetGroupAssignments.remove(targetId);
    } else {
      _targetGroupAssignments[targetId] = groupNumber;
    }
    await preferences?.setTargetGroup(targetId, groupNumber);
    notifyListeners();
  }

  /// Emits one [TargetGroup] per persistent group in display order that has
  /// at least one assigned target. Used by Program A setup to seed the
  /// initial drill config when not loading a saved template.
  List<TargetGroup> buildSeededGroups() {
    final result = <TargetGroup>[];
    for (final groupNumber in _targetGroupOrder) {
      final ids = _targetGroupAssignments.entries
          .where((e) => e.value == groupNumber)
          .map((e) => e.key)
          .toList()
        ..sort();
      if (ids.isEmpty) continue;
      result.add(TargetGroup(
        id: groupNumber,
        name: _targetGroupLabels[groupNumber],
        targetIds: ids,
      ));
    }
    return result;
  }

  // --- Walk the range (shared by Home + Target Setup screens) ---

  /// Iterates online targets and identifies each in turn:
  /// TTS-speak resolved display name, send IDENT, wait 2s. No-op when
  /// no targets are online.
  Future<void> walkTheRange() async {
    for (final target in targets.where((t) => t.isOnline)) {
      final name = _targetNames[target.id] ?? 'Target ${target.id}';
      await tts?.speak(name);
      await identifyTarget(target.id);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
```

- [ ] **Step 7: Run test to verify it passes**

Run: `flutter test test/state/app_state_groups_test.dart`
Expected: PASS — all subtests green.

- [ ] **Step 8: Commit**

```bash
git add lib/state/app_state.dart test/state/app_state_groups_test.dart test/helpers/fake_repositories.dart
git commit -m "feat(state): persistent target groups + walkTheRange in AppState"
```

---

## Task 3: Remove dead `TargetUnit.groupId`

**Files:**
- Modify: `lib/models/target_unit.dart`

- [ ] **Step 1: Verify field is unused**

Run: `grep -rn "\.groupId\b\|groupId:" lib/ test/ --include="*.dart"`
Expected: Only the declaration in `target_unit.dart:4` and its constructor parameter at `:19`. If anything else references it, stop and revisit before continuing.

- [ ] **Step 2: Remove field + constructor param**

Edit `lib/models/target_unit.dart` so the class looks like this:

```dart
class TargetUnit {
  final int id;
  bool isOnline;
  bool isNoShoot;

  /// Optional user-assigned name (e.g. "Flipper").
  /// Null means fall back to `T{id}`. Gate 2 persists this via
  /// PreferencesRepository (addendum §4.B).
  String? displayName;

  /// True when ≥3 heartbeats have been missed (addendum §3, §7.6).
  /// Gate 2 wires this from the heartbeat tracker; default false for now.
  bool isUnreachable;

  TargetUnit({
    required this.id,
    this.isOnline = false,
    this.isNoShoot = false,
    this.displayName,
    this.isUnreachable = false,
  });

  /// Human-facing label: user-assigned name if set, else `T{id}`.
  String get label => displayName ?? 'T$id';
}
```

- [ ] **Step 3: Run the full test suite + analyzer**

Run: `flutter analyze && flutter test`
Expected: PASS. If a call site appears with `groupId:` (none expected — Step 1 ruled it out), revert and investigate.

- [ ] **Step 4: Commit**

```bash
git add lib/models/target_unit.dart
git commit -m "refactor(model): drop dead TargetUnit.groupId field"
```

---

## Task 4: Group chip row widget (groups header)

**Files:**
- Create: `lib/widgets/target_setup/group_chip_row.dart`
- Test: `test/widgets/target_setup/group_chip_row_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/widgets/target_setup/group_chip_row_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atriarch/widgets/target_setup/group_chip_row.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders one chip per group in order', (tester) async {
    await tester.pumpWidget(_wrap(GroupChipRow(
      groupOrder: const [1, 3, 2],
      labels: const {1: 'Left bank'},
      onAddGroup: () {},
      onRenameGroup: (_) {},
      onDeleteGroup: (_) {},
    )));
    expect(find.text('G1: Left bank'), findsOneWidget);
    expect(find.text('G3'), findsOneWidget);
    expect(find.text('G2'), findsOneWidget);
    expect(find.text('+ Add group'), findsOneWidget);
  });

  testWidgets('tapping + Add group fires callback', (tester) async {
    var added = 0;
    await tester.pumpWidget(_wrap(GroupChipRow(
      groupOrder: const [],
      labels: const {},
      onAddGroup: () => added++,
      onRenameGroup: (_) {},
      onDeleteGroup: (_) {},
    )));
    await tester.tap(find.text('+ Add group'));
    await tester.pumpAndSettle();
    expect(added, 1);
  });

  testWidgets('tapping a group chip fires rename callback with group number',
      (tester) async {
    int? renamed;
    await tester.pumpWidget(_wrap(GroupChipRow(
      groupOrder: const [1, 2],
      labels: const {},
      onAddGroup: () {},
      onRenameGroup: (g) => renamed = g,
      onDeleteGroup: (_) {},
    )));
    await tester.tap(find.text('G2'));
    await tester.pumpAndSettle();
    expect(renamed, 2);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/target_setup/group_chip_row_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement the widget**

Create `lib/widgets/target_setup/group_chip_row.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/atriarch_theme.dart';

/// Horizontal scrollable chip list of persistent target groups, plus a
/// trailing `+ Add group` action chip.
///
/// Tap on a group chip fires [onRenameGroup]. The screen is responsible for
/// presenting a rename/delete dialog. [onDeleteGroup] is exposed for that
/// dialog's delete action.
class GroupChipRow extends StatelessWidget {
  final List<int> groupOrder;
  final Map<int, String> labels;
  final VoidCallback onAddGroup;
  final void Function(int groupNumber) onRenameGroup;
  final void Function(int groupNumber) onDeleteGroup;

  const GroupChipRow({
    super.key,
    required this.groupOrder,
    required this.labels,
    required this.onAddGroup,
    required this.onRenameGroup,
    required this.onDeleteGroup,
  });

  String _chipLabel(int groupNumber) {
    final label = labels[groupNumber];
    return (label == null || label.isEmpty)
        ? 'G$groupNumber'
        : 'G$groupNumber: $label';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groupOrder.length + 1,
        separatorBuilder: (_, __) =>
            const SizedBox(width: AtriarchSpacing.sm),
        itemBuilder: (context, i) {
          if (i == groupOrder.length) {
            return ActionChip(
              label: const Text('+ Add group'),
              onPressed: onAddGroup,
            );
          }
          final g = groupOrder[i];
          return InputChip(
            label: Text(_chipLabel(g)),
            onPressed: () => onRenameGroup(g),
            backgroundColor: tokens.bgCard,
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/target_setup/group_chip_row_test.dart`
Expected: PASS — three tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/target_setup/group_chip_row.dart test/widgets/target_setup/group_chip_row_test.dart
git commit -m "feat(setup): group chip row widget"
```

---

## Task 5: Per-row group picker widget

**Files:**
- Create: `lib/widgets/target_setup/group_picker.dart`
- Test: `test/widgets/target_setup/group_picker_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/widgets/target_setup/group_picker_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atriarch/widgets/target_setup/group_picker.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows "None" when assignment is null', (tester) async {
    await tester.pumpWidget(_wrap(GroupPicker(
      currentGroup: null,
      groupOrder: const [1, 2],
      labels: const {},
      onSelect: (_) {},
      onCreateNew: () async => 3,
    )));
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('shows label when assigned', (tester) async {
    await tester.pumpWidget(_wrap(GroupPicker(
      currentGroup: 1,
      groupOrder: const [1],
      labels: const {1: 'Left bank'},
      onSelect: (_) {},
      onCreateNew: () async => 2,
    )));
    expect(find.text('G1: Left bank'), findsOneWidget);
  });

  testWidgets('selecting a group calls onSelect', (tester) async {
    int? selected = -1;
    await tester.pumpWidget(_wrap(GroupPicker(
      currentGroup: null,
      groupOrder: const [1, 2],
      labels: const {},
      onSelect: (g) => selected = g,
      onCreateNew: () async => 3,
    )));
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('G2').last);
    await tester.pumpAndSettle();
    expect(selected, 2);
  });

  testWidgets('selecting None calls onSelect(null)', (tester) async {
    int? selected = 99;
    await tester.pumpWidget(_wrap(GroupPicker(
      currentGroup: 1,
      groupOrder: const [1],
      labels: const {},
      onSelect: (g) => selected = g,
      onCreateNew: () async => 2,
    )));
    await tester.tap(find.text('G1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None').last);
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });

  testWidgets('+ New group calls onCreateNew then onSelect', (tester) async {
    int? selected = -1;
    await tester.pumpWidget(_wrap(GroupPicker(
      currentGroup: null,
      groupOrder: const [1],
      labels: const {},
      onSelect: (g) => selected = g,
      onCreateNew: () async => 7,
    )));
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ New group…'));
    await tester.pumpAndSettle();
    expect(selected, 7);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/target_setup/group_picker_test.dart`
Expected: FAIL — `GroupPicker` not defined.

- [ ] **Step 3: Implement the widget**

Create `lib/widgets/target_setup/group_picker.dart`:

```dart
import 'package:flutter/material.dart';

/// Per-row group selection menu. Shows the current assignment as a chip
/// label; tapping opens a popup with `None`, every existing group, and
/// `+ New group…` at the bottom. Selecting "New group" awaits
/// [onCreateNew] for the newly minted group number and then calls
/// [onSelect] with it.
class GroupPicker extends StatelessWidget {
  final int? currentGroup;
  final List<int> groupOrder;
  final Map<int, String> labels;
  final void Function(int? groupNumber) onSelect;
  final Future<int> Function() onCreateNew;

  const GroupPicker({
    super.key,
    required this.currentGroup,
    required this.groupOrder,
    required this.labels,
    required this.onSelect,
    required this.onCreateNew,
  });

  static const _newGroupSentinel = -1;
  static const _noneSentinel = -2;

  String _chipLabel(int g) {
    final l = labels[g];
    return (l == null || l.isEmpty) ? 'G$g' : 'G$g: $l';
  }

  String get _currentLabel =>
      currentGroup == null ? 'None' : _chipLabel(currentGroup!);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Assign group',
      child: Chip(
        label: Text(_currentLabel),
        avatar: const Icon(Icons.expand_more, size: 18),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem<int>(
          value: _noneSentinel,
          child: Text('None'),
        ),
        for (final g in groupOrder)
          PopupMenuItem<int>(
            value: g,
            child: Text(_chipLabel(g)),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<int>(
          value: _newGroupSentinel,
          child: Text('+ New group…'),
        ),
      ],
      onSelected: (value) async {
        if (value == _noneSentinel) {
          onSelect(null);
        } else if (value == _newGroupSentinel) {
          final created = await onCreateNew();
          onSelect(created);
        } else {
          onSelect(value);
        }
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/target_setup/group_picker_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/target_setup/group_picker.dart test/widgets/target_setup/group_picker_test.dart
git commit -m "feat(setup): per-row group picker widget"
```

---

## Task 6: Target row widget

**Files:**
- Create: `lib/widgets/target_setup/target_row.dart`
- Test: `test/widgets/target_setup/target_row_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/widgets/target_setup/target_row_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atriarch/widgets/target_setup/target_row.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders id, optional name, and online status', (tester) async {
    await tester.pumpWidget(_wrap(TargetRow(
      targetId: 3,
      displayName: 'Alpha',
      isOnline: true,
      currentGroup: null,
      groupOrder: const [],
      labels: const {},
      onSelectGroup: (_) {},
      onCreateNewGroup: () async => 1,
      onFlash: () {},
    )));
    expect(find.text('Target 3'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('online'), findsOneWidget);
  });

  testWidgets('tapping flash fires callback when online', (tester) async {
    var flashed = 0;
    await tester.pumpWidget(_wrap(TargetRow(
      targetId: 3,
      displayName: null,
      isOnline: true,
      currentGroup: null,
      groupOrder: const [],
      labels: const {},
      onSelectGroup: (_) {},
      onCreateNewGroup: () async => 1,
      onFlash: () => flashed++,
    )));
    await tester.tap(find.byTooltip('Flash LED'));
    await tester.pumpAndSettle();
    expect(flashed, 1);
  });

  testWidgets('flash button is disabled when offline', (tester) async {
    var flashed = 0;
    await tester.pumpWidget(_wrap(TargetRow(
      targetId: 3,
      displayName: null,
      isOnline: false,
      currentGroup: null,
      groupOrder: const [],
      labels: const {},
      onSelectGroup: (_) {},
      onCreateNewGroup: () async => 1,
      onFlash: () => flashed++,
    )));
    final iconButton = tester.widget<IconButton>(find.byTooltip('Flash LED'));
    expect(iconButton.onPressed, isNull);
    expect(flashed, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/target_setup/target_row_test.dart`
Expected: FAIL — `TargetRow` not defined.

- [ ] **Step 3: Implement the widget**

Create `lib/widgets/target_setup/target_row.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/atriarch_theme.dart';
import 'group_picker.dart';

class TargetRow extends StatelessWidget {
  final int targetId;
  final String? displayName;
  final bool isOnline;
  final int? currentGroup;
  final List<int> groupOrder;
  final Map<int, String> labels;
  final void Function(int? groupNumber) onSelectGroup;
  final Future<int> Function() onCreateNewGroup;
  final VoidCallback onFlash;

  const TargetRow({
    super.key,
    required this.targetId,
    required this.displayName,
    required this.isOnline,
    required this.currentGroup,
    required this.groupOrder,
    required this.labels,
    required this.onSelectGroup,
    required this.onCreateNewGroup,
    required this.onFlash,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AtriarchSpacing.sm),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.circle : Icons.circle_outlined,
            size: 12,
            color: isOnline ? tokens.statusLive : tokens.textTertiary,
          ),
          const SizedBox(width: AtriarchSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Target $targetId',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (displayName != null && displayName!.isNotEmpty)
                  Text(
                    displayName!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                  )
                else if (!isOnline)
                  Text(
                    'offline',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textTertiary,
                        ),
                  )
                else
                  Text(
                    'online',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                  ),
              ],
            ),
          ),
          GroupPicker(
            currentGroup: currentGroup,
            groupOrder: groupOrder,
            labels: labels,
            onSelect: onSelectGroup,
            onCreateNew: onCreateNewGroup,
          ),
          const SizedBox(width: AtriarchSpacing.sm),
          IconButton(
            tooltip: 'Flash LED',
            icon: const Icon(Icons.flash_on),
            onPressed: isOnline ? onFlash : null,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/target_setup/target_row_test.dart`
Expected: PASS — three subtests green.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/target_setup/target_row.dart test/widgets/target_setup/target_row_test.dart
git commit -m "feat(setup): target row widget with flash + group picker"
```

---

## Task 7: Rewrite TargetSetupScreen

**Files:**
- Modify: `lib/screens/target_setup_screen.dart`

- [ ] **Step 1: Replace screen body**

Overwrite `lib/screens/target_setup_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_primary_button.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/target_setup/group_chip_row.dart';
import '../widgets/target_setup/target_row.dart';

class TargetSetupScreen extends StatefulWidget {
  const TargetSetupScreen({super.key});

  @override
  State<TargetSetupScreen> createState() => _TargetSetupScreenState();
}

class _TargetSetupScreenState extends State<TargetSetupScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // ignore: discarded_futures
      _runDiscovery();
    });
  }

  Future<void> _runDiscovery() async {
    try {
      await context.read<AppState>().discoverTargets();
    } catch (_) {
      // Silent — online count staying at zero is the signal.
    }
  }

  Future<void> _onWalkTheRange() async {
    await context.read<AppState>().walkTheRange();
  }

  Future<void> _renameGroupDialog(BuildContext context, int groupNumber) async {
    final state = context.read<AppState>();
    final controller = TextEditingController(
      text: state.targetGroupLabels[groupNumber] ?? '',
    );
    final result = await showDialog<_GroupDialogResult>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Group $groupNumber'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Label (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
                ctx, const _GroupDialogResult.delete()),
            child: const Text('Delete group'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, _GroupDialogResult.save(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result.isDelete) {
      await state.deleteTargetGroup(groupNumber);
    } else {
      await state.renameTargetGroup(
        groupNumber,
        result.label!.isEmpty ? null : result.label,
      );
    }
  }

  Future<int> _createGroupAndRename(BuildContext context) async {
    final state = context.read<AppState>();
    final number = await state.createTargetGroup();
    if (mounted) {
      await _renameGroupDialog(context, number);
    }
    return number;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalScaffold(
      title: 'TARGET SETUP',
      body: Padding(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        child: Consumer<AppState>(
          builder: (_, state, __) {
            final total = state.targets.length;
            final online = state.targets.where((t) => t.isOnline).length;
            final denominator = total == 0 ? '?' : total.toString();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(AtriarchSpacing.md),
                  decoration: BoxDecoration(
                    color: tokens.bgCard,
                    borderRadius: BorderRadius.circular(AtriarchRadius.md),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Row(
                    children: [
                      if (state.isScanning)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      else
                        Icon(
                          online > 0 ? Icons.check_circle : Icons.radar,
                          color: online > 0
                              ? tokens.statusLive
                              : tokens.textTertiary,
                        ),
                      const SizedBox(width: AtriarchSpacing.md),
                      Expanded(
                        child: Text(
                          '$online of $denominator targets online',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AtriarchSpacing.lg),
                Text('GROUPS',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: AtriarchSpacing.sm),
                GroupChipRow(
                  groupOrder: state.targetGroupOrder,
                  labels: state.targetGroupLabels,
                  onAddGroup: () => _createGroupAndRename(context),
                  onRenameGroup: (g) => _renameGroupDialog(context, g),
                  onDeleteGroup: (g) => state.deleteTargetGroup(g),
                ),
                const SizedBox(height: AtriarchSpacing.lg),
                Text('TARGETS',
                    style: Theme.of(context).textTheme.labelMedium),
                Expanded(
                  child: state.targets.isEmpty
                      ? Center(
                          child: Text(
                            'No targets discovered yet.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: tokens.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          itemCount: state.targets.length,
                          separatorBuilder: (_, __) => Divider(
                            color: tokens.border,
                            height: 1,
                          ),
                          itemBuilder: (_, i) {
                            final t = state.targets[i];
                            return TargetRow(
                              targetId: t.id,
                              displayName: state.targetNames[t.id],
                              isOnline: t.isOnline,
                              currentGroup:
                                  state.targetGroupAssignments[t.id],
                              groupOrder: state.targetGroupOrder,
                              labels: state.targetGroupLabels,
                              onSelectGroup: (g) =>
                                  state.setTargetGroup(t.id, g),
                              onCreateNewGroup: () =>
                                  _createGroupAndRename(context),
                              onFlash: () => state.identifyTarget(t.id),
                            );
                          },
                        ),
                ),
                const SizedBox(height: AtriarchSpacing.md),
                TacticalPrimaryButton(
                  label: 'WALK_THE_RANGE',
                  icon: Icons.directions_walk,
                  onPressed: _onWalkTheRange,
                ),
                const SizedBox(height: AtriarchSpacing.sm),
                const TacticalPrimaryButton(
                  label: 'PHOTO_MAP',
                  icon: Icons.photo_camera_outlined,
                  variant: TacticalButtonVariant.disabled,
                ),
                const SizedBox(height: AtriarchSpacing.sm),
                TacticalPrimaryButton(
                  label: 'RESCAN',
                  onPressed: _runDiscovery,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GroupDialogResult {
  final bool isDelete;
  final String? label;
  const _GroupDialogResult.save(this.label) : isDelete = false;
  const _GroupDialogResult.delete()
      : isDelete = true,
        label = null;
}
```

- [ ] **Step 2: Run analyzer and full test suite**

Run: `flutter analyze && flutter test`
Expected: PASS. Investigate any failures before proceeding.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/target_setup_screen.dart
git commit -m "feat(setup): rewrite target setup screen with target list + groups"
```

---

## Task 8: Delegate home-screen walk-the-range to AppState

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: Replace the inline walk loop**

In `lib/screens/home_screen.dart`, replace the `_startWalkTheRange` method (currently at lines 122-131) with:

```dart
  Future<void> _startWalkTheRange(BuildContext context) async {
    await context.read<AppState>().walkTheRange();
  }
```

Remove the now-unused import for `TargetNameResolver` if it is no longer referenced anywhere else in this file (run `grep TargetNameResolver lib/screens/home_screen.dart` first — keep the import only if other uses exist).

- [ ] **Step 2: Run analyzer + tests**

Run: `flutter analyze && flutter test`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "refactor(home): delegate walk-the-range to AppState"
```

---

## Task 9: Seed Program A drill groups from persistent state

**Files:**
- Modify: `lib/screens/program_a_setup_screen.dart`
- Test: `test/screens/program_a_seeded_groups_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/screens/program_a_seeded_groups_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:atriarch/screens/program_a_setup_screen.dart';
import 'package:atriarch/services/preferences_repository.dart';
import 'package:atriarch/state/app_state.dart';

import '../helpers/fake_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seeds initial groups from AppState.buildSeededGroups()',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'target_groups': '{"7":1,"8":1,"9":2}',
      'target_group_labels': '{"1":"Left bank"}',
      'target_group_order': '1,2',
    });
    final prefs = PreferencesRepository(await SharedPreferences.getInstance());
    final state = AppState.forTesting(
      sessions: FakeSessionRepository(),
      shooterState: FakeShooterState(),
      preferences: prefs,
    );
    await state.hydratePreferences();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: ProgramASetupScreen()),
      ),
    );
    await tester.pump();

    // Group chips for G1 (label "Left bank") and G2 should render.
    expect(find.textContaining('Left bank'), findsOneWidget);
    expect(find.textContaining('Group 2'), findsOneWidget);
  });
}
```

(If the chip widget in Program A renders group names differently — e.g.
showing `G1` instead of `Left bank` — adjust the `expect` matchers after
running once and inspecting `tester.binding.renderViewElement`. The
existing rendering of `TargetGroup.name` is the contract here; the seed
just supplies it.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/program_a_seeded_groups_test.dart`
Expected: FAIL — seeded groups not rendered because initial state is still `List.generate(5, ...)`.

- [ ] **Step 3: Read current init to confirm seed location**

Open `lib/screens/program_a_setup_screen.dart`. The current field at line 48 is:

```dart
List<TargetGroup> groups = List.generate(5, (i) => TargetGroup(id: i + 1));
```

This is initialized inline. Move it to be assigned during `initState` from `AppState.buildSeededGroups()`, with a fallback to the original five-group default when seeding yields nothing.

- [ ] **Step 4: Replace inline init with seeded init**

In `lib/screens/program_a_setup_screen.dart`:

1. Change the field declaration on line 48 to:

```dart
List<TargetGroup> groups = <TargetGroup>[];
```

2. Inside `initState()` (after the existing `addPostFrameCallback` registrations), add a third callback that seeds groups once `AppState` is available:

```dart
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      final seeded = state.buildSeededGroups();
      setState(() {
        groups = seeded.isNotEmpty
            ? seeded
            : List.generate(5, (i) => TargetGroup(id: i + 1));
      });
    });
```

3. Confirm that the existing template-loading path (around lines 314, where `groups = loaded;` runs) still overrides this seed when a template is chosen. It runs later in response to user action, so seeded groups never collide with template groups.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/screens/program_a_seeded_groups_test.dart`
Expected: PASS. If the matcher in Step 1 was wrong because the chip strip renders text differently, fix the `expect` line and re-run — do not weaken the assertion to "any text".

- [ ] **Step 6: Run full analyzer + tests**

Run: `flutter analyze && flutter test`
Expected: PASS across the suite.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/program_a_setup_screen.dart test/screens/program_a_seeded_groups_test.dart
git commit -m "feat(program-a): seed initial groups from persistent assignments"
```

---

## Task 10: End-to-end smoke test for the setup screen

**Files:**
- Create: `test/screens/target_setup_screen_smoke_test.dart`

- [ ] **Step 1: Write the smoke test**

Create `test/screens/target_setup_screen_smoke_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:atriarch/models/target_unit.dart';
import 'package:atriarch/screens/target_setup_screen.dart';
import 'package:atriarch/services/preferences_repository.dart';
import 'package:atriarch/state/app_state.dart';

import '../helpers/fake_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AppState> _bootState() async {
    final prefs = PreferencesRepository(await SharedPreferences.getInstance());
    final s = AppState.forTesting(
      sessions: FakeSessionRepository(),
      shooterState: FakeShooterState(),
      preferences: prefs,
    );
    s.targets
      ..clear()
      ..addAll([
        TargetUnit(id: 1, isOnline: true),
        TargetUnit(id: 2, isOnline: false),
      ]);
    await s.hydratePreferences();
    return s;
  }

  testWidgets('renders target list with status + group picker + flash',
      (tester) async {
    final s = await _bootState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: s,
        child: const MaterialApp(home: TargetSetupScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Target 1'), findsOneWidget);
    expect(find.text('Target 2'), findsOneWidget);
    expect(find.text('online'), findsOneWidget);
    expect(find.text('offline'), findsOneWidget);
    expect(find.byTooltip('Flash LED'), findsNWidgets(2));
    expect(find.text('+ Add group'), findsOneWidget);
  });

  testWidgets('flash button disabled when target offline', (tester) async {
    final s = await _bootState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: s,
        child: const MaterialApp(home: TargetSetupScreen()),
      ),
    );
    await tester.pump();

    final flashButtons = tester.widgetList<IconButton>(
      find.byTooltip('Flash LED'),
    );
    final enabledStates = flashButtons.map((b) => b.onPressed != null).toList();
    // Order matches target list order: Target 1 (online) enabled, Target 2 (offline) disabled.
    expect(enabledStates, [true, false]);
  });
}
```

- [ ] **Step 2: Run test**

Run: `flutter test test/screens/target_setup_screen_smoke_test.dart`
Expected: PASS.

- [ ] **Step 3: Run analyzer + entire test suite as a final gate**

Run: `flutter analyze && flutter test`
Expected: PASS, no analyzer warnings introduced.

- [ ] **Step 4: Commit**

```bash
git add test/screens/target_setup_screen_smoke_test.dart
git commit -m "test(setup): smoke test for target setup screen"
```

---

## Self-review notes

- **Spec coverage:**
  - § Walk-the-Range dedup → Task 2 (`walkTheRange` in AppState), Task 7 (setup screen calls it), Task 8 (home screen calls it).
  - § Target list with per-row actions → Task 6 (`TargetRow`), Task 7 (screen wires it).
  - § Persistent group storage (3 keys) → Task 1.
  - § AppState API (`createTargetGroup`, `setTargetGroup`, `renameTargetGroup`, `deleteTargetGroup`, `buildSeededGroups`, `walkTheRange`) → Task 2.
  - § Drill seeding (Program A only) → Task 9. Program B does not use `TargetGroup` and is not modified.
  - § `TargetUnit.groupId` removal → Task 3.
  - § Group chip row + add/rename/delete → Task 4 (widget) + Task 7 (screen-side dialog).
  - § Per-row group picker with "+ New group" → Task 5.
  - § Testing (unit + widget, no FFI sqflite) → Tasks 1, 2, 4, 5, 6, 9, 10.
- **Placeholder scan:** no TBDs, every step has concrete code.
- **Type consistency:** `groupOrder: List<int>`, `labels: Map<int,String>`, `currentGroup: int?`, `onCreateNewGroup` (Task 6) wraps `onCreateNew` (Task 5) — consistent.
- **Out-of-scope confirmation:** battery indicator, photo-map, drag reorder — all explicitly skipped, matches spec.
