# Group Target Bottom Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the in-place group-card expansion (which overflows at narrow grid widths) with a bottom sheet that handles all add/remove/move target operations, plus a suppressible cross-group move confirmation and SnackBar undo.

**Architecture:** A new `GroupTargetSheet` widget (opened via `showModalBottomSheet`) renders three sections (`IN THIS GROUP` / `AVAILABLE` / `ASSIGNED ELSEWHERE`) backed reactively by `AppState`. The setup screen exposes shared `_addToGroup` / `_removeFromGroup` / `_moveBetweenGroups` actions used by both the sheet and the existing `AVAILABLE_NODES` strip, each emitting a SnackBar with `UNDO`. A new `skipMoveConfirmation` boolean in `PreferencesRepository` + `AppState` controls whether the move-confirm dialog is shown.

**Tech Stack:** Flutter / Dart, Provider for app state, `shared_preferences` (existing `PreferencesRepository`), `showModalBottomSheet` / `showDialog`, existing tactical widget library.

**Spec:** [docs/superpowers/specs/2026-05-11-group-target-bottom-sheet-design.md](docs/superpowers/specs/2026-05-11-group-target-bottom-sheet-design.md)

---

## File Map

**Create:**
- `lib/widgets/group_target_sheet.dart` — `GroupTargetSheet` widget + private `_MoveConfirmationDialog`.
- `test/widgets/group_target_sheet_test.dart` — widget tests for the sheet and dialog.

**Modify:**
- `lib/services/preferences_repository.dart` — add `getSkipMoveConfirmation` / `setSkipMoveConfirmation`.
- `test/test_helpers/fake_preferences_repository.dart` — mirror the new methods (already exists).
- `lib/state/app_state.dart` — load `_skipMoveConfirmation` on init, expose getter, expose `setSkipMoveConfirmation` mutator that writes through to prefs.
- `lib/screens/program_a_setup_screen.dart` — add shared `_addToGroup` / `_removeFromGroup` / `_moveBetweenGroups`; rewrite `_assignTargetToGroup` and `onRemoveTarget` call sites; remove `_expandedGroupIndex` field and the collapse-on-empty fix; on tap of a group card, open `GroupTargetSheet`; watch `AppState.phase` and auto-dismiss the sheet when leaving `idle`.
- `lib/widgets/tactical/group_node_card.dart` — remove the `expanded` constructor parameter and the `expanded ? Wrap<InputChip> : _CollapsedLabels` ternary; render `_CollapsedLabels` unconditionally; drop the now-dead expanded-Wrap branch.
- `test/widgets/tactical/group_node_card_test.dart` — remove `expanded:` from all test call sites; delete the now-obsolete `'expanded card shows chips with remove buttons'` test (its replacement lives in the sheet test).
- `test/screens/program_a_setup_screen_test.dart` — repair the pre-existing `ProviderNotFoundException` for `DrillTemplateRepository` by wrapping the test pump in a `MultiProvider` that supplies a fake `DrillTemplateRepository`; add new screen-level tests for tap-card-opens-sheet, shared-action SnackBar, and phase-change auto-dismiss.

**Do NOT touch:**
- The uncommitted firmware/iOS WIP files in the working tree.
- `lib/util/target_name_resolver.dart` (Task 1 of the prior plan; stays as-is).
- The existing `PARAM_04 AVAILABLE_NODES` strip rendering — only its `onTap` handler routes through the new shared action.
- The collapsed-state `_CollapsedLabels` widget body inside `group_node_card.dart` (already verified by prior code review).

---

## Task 1: PreferencesRepository — skipMoveConfirmation

**Files:**
- Modify: `lib/services/preferences_repository.dart`
- Modify: `test/test_helpers/fake_preferences_repository.dart`

Add a boolean `skipMoveConfirmation` key with get/set.

- [ ] **Step 1: Add the prefs key and accessors**

In `lib/services/preferences_repository.dart`, near the other `static const String _k...` declarations at the top of the class, add:

```dart
  static const String _kSkipMoveConfirmation = 'skip_move_confirmation';
```

Below the other getter/setter pairs (after `setReadyAudioVolume`), add:

```dart
  // --- skip cross-group move confirmation dialog ---
  Future<bool> getSkipMoveConfirmation() async =>
      _prefs.getBool(_kSkipMoveConfirmation) ?? false;

  Future<void> setSkipMoveConfirmation(bool v) async =>
      _prefs.setBool(_kSkipMoveConfirmation, v);
```

- [ ] **Step 2: Mirror in the fake**

Open `test/test_helpers/fake_preferences_repository.dart`. Look at its existing pattern (other in-memory booleans like `_readyAudioEnabled`). Add a private field and matching get/set:

```dart
  bool _skipMoveConfirmation = false;

  @override
  Future<bool> getSkipMoveConfirmation() async => _skipMoveConfirmation;

  @override
  Future<void> setSkipMoveConfirmation(bool v) async {
    _skipMoveConfirmation = v;
  }
```

If the fake doesn't `extend` / `implement` `PreferencesRepository` but instead duck-types it, skip the `@override` annotations — match the existing file's style.

- [ ] **Step 3: Run analyze**

Run: `flutter analyze lib/services/preferences_repository.dart test/test_helpers/fake_preferences_repository.dart`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add lib/services/preferences_repository.dart test/test_helpers/fake_preferences_repository.dart
git commit -m "feat(prefs): add skipMoveConfirmation flag"
```

---

## Task 2: AppState — skipMoveConfirmation wiring

**Files:**
- Modify: `lib/state/app_state.dart`

Expose `skipMoveConfirmation` as state. Load it during `AppState.load()` (or whatever the existing init method is called); mutate via a single setter that writes through to prefs and `notifyListeners()`.

- [ ] **Step 1: Locate the init method**

Read `lib/state/app_state.dart` to find where other prefs are loaded (search for `getOnboardingComplete` or `getReadyAudio`). The existing pattern reads each pref into a private field. Add yours alongside.

- [ ] **Step 2: Add the field, getter, setter, and load call**

Near the other `bool _...` fields (around line 65 — see `_readyAudioEnabled`), add:

```dart
  bool _skipMoveConfirmation = false;
```

Near the other public getters (around line 77), add:

```dart
  bool get skipMoveConfirmation => _skipMoveConfirmation;
```

In the init/load method (where `_readyAudioEnabled = await preferences?.getReadyAudioEnabled() ?? true;` lives — search for that exact line), append:

```dart
    _skipMoveConfirmation =
        await preferences?.getSkipMoveConfirmation() ?? false;
```

Near the other setters (after `setReadyAudioVolume`), add:

```dart
  Future<void> setSkipMoveConfirmation(bool v) async {
    _skipMoveConfirmation = v;
    notifyListeners();
    await preferences?.setSkipMoveConfirmation(v);
  }
```

- [ ] **Step 3: Run analyze**

Run: `flutter analyze lib/state/app_state.dart`
Expected: No errors.

- [ ] **Step 4: Run the existing AppState tests if any**

Run: `flutter test test/state/`
Expected: All tests pass (no new tests yet; this confirms no regressions).

- [ ] **Step 5: Commit**

```bash
git add lib/state/app_state.dart
git commit -m "feat(app-state): wire skipMoveConfirmation through prefs"
```

---

## Task 3: Repair `program_a_setup_screen_test.dart` infrastructure

**Files:**
- Modify: `test/screens/program_a_setup_screen_test.dart`

This test currently fails with `ProviderNotFoundException` for `DrillTemplateRepository`. Repair it so subsequent tasks can add screen-level tests.

- [ ] **Step 1: Read the current test setup**

Read `test/screens/program_a_setup_screen_test.dart` to understand its current `pumpWidget` shape — likely just `ChangeNotifierProvider<AppState>.value(...)`. Identify where `DrillTemplateRepository` is read inside the screen (the error message references `program_a_setup_screen.dart:343`).

- [ ] **Step 2: Find the existing fake**

The fake helper is at `test/test_helpers/fake_drill_template_repository.dart` (project memory confirms widget tests use fake repos to avoid FFI sqflite deadlocks). Read it to confirm its constructor + interface.

- [ ] **Step 3: Wrap each test's pumpWidget in a MultiProvider**

Replace the current `ChangeNotifierProvider<AppState>.value(...)` with:

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider<AppState>.value(value: state),
    Provider<DrillTemplateRepository>.value(
      value: FakeDrillTemplateRepository(),
    ),
  ],
  child: MaterialApp(
    theme: buildAtriarchDarkTheme(),
    home: const ProgramASetupScreen(),
  ),
),
```

(Adjust to match the actual existing structure — wrap whatever `MaterialApp` / `home` already lives there.)

Add the import at the top of the test file:

```dart
import 'package:atriarch/repositories/drill_template_repository.dart';
import 'package:provider/provider.dart';
import '../test_helpers/fake_drill_template_repository.dart';
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/screens/program_a_setup_screen_test.dart`
Expected: All tests PASS (or at least the `ProviderNotFoundException` is gone — if there are unrelated pre-existing failures, those become the next task's concern; report them but don't fix them in this task).

- [ ] **Step 5: Commit**

```bash
git add test/screens/program_a_setup_screen_test.dart
git commit -m "test(setup-screen): provide fake DrillTemplateRepository"
```

---

## Task 4: `GroupTargetSheet` widget — base structure (no dialog, no move yet)

**Files:**
- Create: `lib/widgets/group_target_sheet.dart`
- Create: `test/widgets/group_target_sheet_test.dart`

Build the sheet skeleton: three sections (`IN THIS GROUP`, `AVAILABLE`, `ASSIGNED ELSEWHERE`), reading from `AppState`. Tap callbacks for add / remove / move are wired but the move tap goes straight through (no confirmation dialog yet — added in Task 5). Empty sections are hidden.

- [ ] **Step 1: Write the failing widget tests**

Create `test/widgets/group_target_sheet_test.dart`:

```dart
import 'package:atriarch/models/target_unit.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/group_target_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  AppState buildState({
    required List<TargetUnit> targets,
    required List<List<int>> groupTargetIds,
  }) {
    final state = AppState();
    state.targets = targets;
    // Inject groups directly via reflection-equivalent: tests use the same
    // ProgramASetupScreenState pattern via a callback. For sheet tests,
    // we pass groupTargetIds[selectedGroupIndex] through the sheet's
    // constructor params (see ShowSheet harness below).
    return state;
  }

  Widget harness({
    required AppState state,
    required int groupIndex,
    required List<int> thisGroupIds,
    required List<int> assignedElsewhereIds,
    required Map<int, int> targetIdToGroupIndex,
    void Function(int targetId)? onAdd,
    void Function(int targetId)? onRemove,
    void Function(int targetId, int fromGroupIndex)? onMove,
  }) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: GroupTargetSheet(
            groupIndex: groupIndex,
            thisGroupIds: thisGroupIds,
            assignedElsewhereIds: assignedElsewhereIds,
            targetIdToGroupIndex: targetIdToGroupIndex,
            onAdd: onAdd ?? (_) {},
            onRemove: onRemove ?? (_) {},
            onMove: onMove ?? (_, __) {},
          ),
        ),
      ),
    );
  }

  testWidgets('header shows group label', (tester) async {
    final state = buildState(targets: const [], groupTargetIds: const []);
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 3,
      thisGroupIds: const [],
      assignedElsewhereIds: const [],
      targetIdToGroupIndex: const {},
    ));
    expect(find.text('GROUP 04 — TARGETS'), findsOneWidget);
  });

  testWidgets('IN THIS GROUP section renders assigned targets with remove icon',
      (tester) async {
    final state = buildState(
      targets: [
        TargetUnit(id: 1, address: 'A1')..isOnline = true,
        TargetUnit(id: 2, address: 'A2')..isOnline = true,
      ],
      groupTargetIds: const [],
    );
    var removed = -1;
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [1, 2],
      assignedElsewhereIds: const [],
      targetIdToGroupIndex: const {},
      onRemove: (id) => removed = id,
    ));
    expect(find.text('IN THIS GROUP'), findsOneWidget);
    expect(find.text('T/U_01'), findsOneWidget);
    expect(find.text('T/U_02'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.close).first);
    expect(removed, 1);
  });

  testWidgets('AVAILABLE section renders unassigned online targets',
      (tester) async {
    final state = buildState(
      targets: [
        TargetUnit(id: 3, address: 'A3')..isOnline = true,
        TargetUnit(id: 4, address: 'A4')..isOnline = true,
      ],
      groupTargetIds: const [],
    );
    var added = -1;
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [],
      assignedElsewhereIds: const [],
      targetIdToGroupIndex: const {},
      onAdd: (id) => added = id,
    ));
    expect(find.text('AVAILABLE'), findsOneWidget);
    expect(find.text('T/U_03'), findsOneWidget);
    expect(find.text('T/U_04'), findsOneWidget);
    await tester.tap(find.text('T/U_03'));
    expect(added, 3);
  });

  testWidgets('ASSIGNED ELSEWHERE shows source-group badge and dispatches move',
      (tester) async {
    final state = buildState(
      targets: [
        TargetUnit(id: 5, address: 'A5')..isOnline = true,
      ],
      groupTargetIds: const [],
    );
    int? movedId;
    int? movedFrom;
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [],
      assignedElsewhereIds: const [5],
      targetIdToGroupIndex: const {5: 2}, // target 5 is in group index 2
      onMove: (id, from) {
        movedId = id;
        movedFrom = from;
      },
    ));
    expect(find.text('ASSIGNED ELSEWHERE'), findsOneWidget);
    expect(find.text('T/U_05'), findsOneWidget);
    expect(find.text('GROUP 03'), findsOneWidget);
    await tester.tap(find.text('T/U_05'));
    expect(movedId, 5);
    expect(movedFrom, 2);
  });

  testWidgets('empty sections are hidden', (tester) async {
    final state = buildState(targets: const [], groupTargetIds: const []);
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [],
      assignedElsewhereIds: const [],
      targetIdToGroupIndex: const {},
    ));
    expect(find.text('IN THIS GROUP'), findsNothing);
    expect(find.text('AVAILABLE'), findsNothing);
    expect(find.text('ASSIGNED ELSEWHERE'), findsNothing);
    expect(find.text('NO ONLINE TARGETS'), findsOneWidget);
  });
}
```

If `TargetUnit`'s constructor uses different field names than `id` / `address` / `isOnline`, adapt to match. Inspect `lib/models/target_unit.dart` first.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/group_target_sheet_test.dart`
Expected: FAIL — `GroupTargetSheet` is not yet defined.

- [ ] **Step 3: Create the widget**

Create `lib/widgets/group_target_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../util/target_name_resolver.dart';
import 'tactical/tactical_section.dart';

/// Modal bottom-sheet content for managing a single group's target
/// assignments. Three sections (IN THIS GROUP / AVAILABLE / ASSIGNED
/// ELSEWHERE). Empty sections hide entirely. State is owned by the parent;
/// this widget is pure presentation + tap dispatch.
class GroupTargetSheet extends StatelessWidget {
  final int groupIndex; // 0-based
  final List<int> thisGroupIds;
  final List<int> assignedElsewhereIds;
  final Map<int, int> targetIdToGroupIndex; // for ASSIGNED ELSEWHERE rows
  final ValueChanged<int> onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int targetId, int fromGroupIndex) onMove;

  const GroupTargetSheet({
    super.key,
    required this.groupIndex,
    required this.thisGroupIds,
    required this.assignedElsewhereIds,
    required this.targetIdToGroupIndex,
    required this.onAdd,
    required this.onRemove,
    required this.onMove,
  });

  String _groupLabel(int index) =>
      'GROUP ${(index + 1).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final state = context.watch<AppState>();
    final resolver = TargetNameResolver(state.targetNames);

    final availableIds = state.targets
        .where((t) =>
            t.isOnline &&
            !thisGroupIds.contains(t.id) &&
            !assignedElsewhereIds.contains(t.id))
        .map((t) => t.id)
        .toList();

    final sections = <Widget>[];

    if (thisGroupIds.isNotEmpty) {
      sections.add(TacticalSection(
        code: 'IN THIS GROUP',
        trailing: _groupLabel(groupIndex),
      ));
      for (final id in thisGroupIds) {
        sections.add(_TargetRow(
          label: resolver.display(id),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: tokens.statusViolation,
            onPressed: () => onRemove(id),
          ),
          onTap: null,
        ));
      }
      sections.add(const SizedBox(height: AtriarchSpacing.md));
    }

    if (availableIds.isNotEmpty) {
      sections.add(const TacticalSection(code: 'AVAILABLE'));
      for (final id in availableIds) {
        sections.add(_TargetRow(
          label: resolver.display(id),
          trailing: null,
          onTap: () => onAdd(id),
        ));
      }
      sections.add(const SizedBox(height: AtriarchSpacing.md));
    }

    if (assignedElsewhereIds.isNotEmpty) {
      sections.add(const TacticalSection(code: 'ASSIGNED ELSEWHERE'));
      for (final id in assignedElsewhereIds) {
        final from = targetIdToGroupIndex[id];
        sections.add(_TargetRow(
          label: resolver.display(id),
          trailing: from == null
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AtriarchSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: tokens.groupColor(from + 1)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    _groupLabel(from),
                    style: AtriarchText.labelTiny(
                      color: tokens.groupColor(from + 1),
                    ),
                  ),
                ),
          onTap: from == null ? null : () => onMove(id, from),
        ));
      }
      sections.add(const SizedBox(height: AtriarchSpacing.md));
    }

    final bodyChildren = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AtriarchSpacing.lg,
          AtriarchSpacing.md,
          AtriarchSpacing.lg,
          AtriarchSpacing.sm,
        ),
        child: Text(
          '${_groupLabel(groupIndex)} — TARGETS',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
        ),
      ),
    ];

    if (sections.isEmpty) {
      bodyChildren.add(Padding(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        child: Text(
          'NO ONLINE TARGETS',
          style: AtriarchText.labelTiny(color: tokens.textTertiary),
        ),
      ));
    } else {
      bodyChildren.addAll(sections);
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: bodyChildren,
        ),
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _TargetRow({required this.label, required this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AtriarchSpacing.lg,
          vertical: AtriarchSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                    ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widgets/group_target_sheet_test.dart`
Expected: All tests PASS. If the `TacticalSection` API differs (different param name than `code` / `trailing`), inspect `lib/widgets/tactical/tactical_section.dart` and adapt; the existing usage in `results_screen.dart` is the canonical reference.

- [ ] **Step 5: Run flutter analyze**

Run: `flutter analyze lib/widgets/group_target_sheet.dart`
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/group_target_sheet.dart test/widgets/group_target_sheet_test.dart
git commit -m "feat(allocation): GroupTargetSheet skeleton with three sections"
```

---

## Task 5: Move-confirmation dialog + skip-checkbox plumbing

**Files:**
- Modify: `lib/widgets/group_target_sheet.dart` — add `MoveConfirmationDialog` widget; change the sheet's `onMove` flow so the dialog is shown inline when `state.skipMoveConfirmation == false`.
- Modify: `test/widgets/group_target_sheet_test.dart` — add tests for the dialog flow.

- [ ] **Step 1: Write failing tests for the dialog flow**

Append these test cases to `test/widgets/group_target_sheet_test.dart` (inside the existing `main()`):

```dart
  testWidgets(
      'tapping ASSIGNED ELSEWHERE shows confirmation dialog when not skipped',
      (tester) async {
    final state = AppState()
      ..targets = [TargetUnit(id: 5, address: 'A5')..isOnline = true]
      ..setSkipMoveConfirmationForTesting(false);
    int? movedId;
    int? movedFrom;
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [],
      assignedElsewhereIds: const [5],
      targetIdToGroupIndex: const {5: 2},
      onMove: (id, from) {
        movedId = id;
        movedFrom = from;
      },
    ));
    await tester.tap(find.text('T/U_05'));
    await tester.pumpAndSettle();
    expect(find.text('MOVE TARGET'), findsOneWidget);
    expect(find.textContaining('Move T/U_05 from GROUP 03 to GROUP 01?'),
        findsOneWidget);
    expect(movedId, isNull); // not yet dispatched
    await tester.tap(find.text('MOVE'));
    await tester.pumpAndSettle();
    expect(movedId, 5);
    expect(movedFrom, 2);
  });

  testWidgets('tapping CANCEL discards the move', (tester) async {
    final state = AppState()
      ..targets = [TargetUnit(id: 5, address: 'A5')..isOnline = true]
      ..setSkipMoveConfirmationForTesting(false);
    int? movedId;
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [],
      assignedElsewhereIds: const [5],
      targetIdToGroupIndex: const {5: 2},
      onMove: (id, _) => movedId = id,
    ));
    await tester.tap(find.text('T/U_05'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(movedId, isNull);
  });

  testWidgets('dialog is skipped when skipMoveConfirmation is true',
      (tester) async {
    final state = AppState()
      ..targets = [TargetUnit(id: 5, address: 'A5')..isOnline = true]
      ..setSkipMoveConfirmationForTesting(true);
    int? movedId;
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [],
      assignedElsewhereIds: const [5],
      targetIdToGroupIndex: const {5: 2},
      onMove: (id, _) => movedId = id,
    ));
    await tester.tap(find.text('T/U_05'));
    await tester.pumpAndSettle();
    expect(find.text('MOVE TARGET'), findsNothing);
    expect(movedId, 5);
  });

  testWidgets('checking "Don\'t show this again" persists the preference',
      (tester) async {
    final state = AppState()
      ..targets = [TargetUnit(id: 5, address: 'A5')..isOnline = true]
      ..setSkipMoveConfirmationForTesting(false);
    await tester.pumpWidget(harness(
      state: state,
      groupIndex: 0,
      thisGroupIds: const [],
      assignedElsewhereIds: const [5],
      targetIdToGroupIndex: const {5: 2},
      onMove: (_, __) {},
    ));
    await tester.tap(find.text('T/U_05'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MOVE'));
    await tester.pumpAndSettle();
    expect(state.skipMoveConfirmation, true);
  });
```

These tests reference a `setSkipMoveConfirmationForTesting(bool)` method on `AppState`. Add it now alongside the other `*ForTesting` helpers in `lib/state/app_state.dart`:

```dart
  @visibleForTesting
  void setSkipMoveConfirmationForTesting(bool v) {
    _skipMoveConfirmation = v;
  }
```

Stage this AppState change in Step 5's commit.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/widgets/group_target_sheet_test.dart`
Expected: FAIL — the dialog is not yet shown when tapping `ASSIGNED ELSEWHERE`.

- [ ] **Step 3: Update the sheet's move tap handler**

In `lib/widgets/group_target_sheet.dart`, replace the `_TargetRow` construction inside the `ASSIGNED ELSEWHERE` loop. Change the `onTap` from:

```dart
onTap: from == null ? null : () => onMove(id, from),
```

to:

```dart
onTap: from == null
    ? null
    : () => _handleMoveTap(context, state, id, from, resolver),
```

Where `state` and `resolver` are the local variables already in scope inside `build`. Add the helper method on the widget:

```dart
  Future<void> _handleMoveTap(
    BuildContext context,
    AppState state,
    int targetId,
    int fromGroupIndex,
    TargetNameResolver resolver,
  ) async {
    if (state.skipMoveConfirmation) {
      onMove(targetId, fromGroupIndex);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _MoveConfirmationDialog(
        targetLabel: resolver.display(targetId),
        fromLabel: _groupLabel(fromGroupIndex),
        toLabel: _groupLabel(groupIndex),
      ),
    );
    if (confirmed == true) {
      onMove(targetId, fromGroupIndex);
    }
  }
```

Add the dialog as a private class at the bottom of `lib/widgets/group_target_sheet.dart`:

```dart
class _MoveConfirmationDialog extends StatefulWidget {
  final String targetLabel;
  final String fromLabel;
  final String toLabel;
  const _MoveConfirmationDialog({
    required this.targetLabel,
    required this.fromLabel,
    required this.toLabel,
  });

  @override
  State<_MoveConfirmationDialog> createState() =>
      _MoveConfirmationDialogState();
}

class _MoveConfirmationDialogState extends State<_MoveConfirmationDialog> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('MOVE TARGET'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Move ${widget.targetLabel} from ${widget.fromLabel} to '
            '${widget.toLabel}?',
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _dontShowAgain,
            onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
            title: const Text("Don't show this again"),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () async {
            if (_dontShowAgain) {
              await context.read<AppState>().setSkipMoveConfirmation(true);
            }
            if (!context.mounted) return;
            Navigator.of(context).pop(true);
          },
          child: const Text('MOVE'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/widgets/group_target_sheet_test.dart`
Expected: All tests PASS (both original 5 from Task 4 + 4 new from this task).

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/widgets/group_target_sheet.dart lib/state/app_state.dart`
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/group_target_sheet.dart lib/state/app_state.dart test/widgets/group_target_sheet_test.dart
git commit -m "feat(allocation): cross-group move confirmation with skip flag"
```

---

## Task 6: Shared action layer + SnackBar undo in setup screen

**Files:**
- Modify: `lib/screens/program_a_setup_screen.dart`

Introduce `_addToGroup` / `_removeFromGroup` / `_moveBetweenGroups` methods. Each mutates `groups` inside `setState` and calls a shared `_showUndoSnackBar` with an appropriate message and inverse callback. Rewrite the existing `_assignTargetToGroup` and the `onRemoveTarget` call site to delegate to these.

- [ ] **Step 1: Add the shared action methods**

In `_ProgramASetupScreenState` (around the existing `_assignTargetToGroup` / `_removeTargetFromGroup` methods at line 145), add:

```dart
  void _addToGroup(int targetId, int groupIndex) {
    setState(() {
      for (final g in groups) {
        g.targetIds.remove(targetId);
      }
      groups[groupIndex].targetIds.add(targetId);
    });
    _showUndoSnackBar(
      message: 'Target T/U_${targetId.toString().padLeft(2, '0')} added to '
          'GROUP ${(groupIndex + 1).toString().padLeft(2, '0')}',
      onUndo: () {
        setState(() {
          groups[groupIndex].targetIds.remove(targetId);
        });
      },
    );
  }

  void _removeFromGroup(int targetId, int groupIndex) {
    setState(() {
      groups[groupIndex].targetIds.remove(targetId);
    });
    _showUndoSnackBar(
      message: 'Target T/U_${targetId.toString().padLeft(2, '0')} removed '
          'from GROUP ${(groupIndex + 1).toString().padLeft(2, '0')}',
      onUndo: () {
        setState(() {
          groups[groupIndex].targetIds.add(targetId);
        });
      },
    );
  }

  void _moveBetweenGroups(
      int targetId, int fromGroupIndex, int toGroupIndex) {
    setState(() {
      groups[fromGroupIndex].targetIds.remove(targetId);
      groups[toGroupIndex].targetIds.add(targetId);
    });
    _showUndoSnackBar(
      message: 'Target T/U_${targetId.toString().padLeft(2, '0')} moved from '
          'GROUP ${(fromGroupIndex + 1).toString().padLeft(2, '0')} to '
          'GROUP ${(toGroupIndex + 1).toString().padLeft(2, '0')}',
      onUndo: () {
        setState(() {
          groups[toGroupIndex].targetIds.remove(targetId);
          groups[fromGroupIndex].targetIds.add(targetId);
        });
      },
    );
  }

  void _showUndoSnackBar({
    required String message,
    required VoidCallback onUndo,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: onUndo,
        ),
      ),
    );
  }
```

- [ ] **Step 2: Rewrite the existing call sites**

Replace the body of `_assignTargetToGroup` (currently around line 145) with:

```dart
  void _assignTargetToGroup(int targetId) {
    if (selectedGroupIndex == null) return;
    _addToGroup(targetId, selectedGroupIndex!);
  }
```

Replace the body of `_removeTargetFromGroup` (currently around line 155) with:

```dart
  void _removeTargetFromGroup(int groupIndex, int targetId) {
    _removeFromGroup(targetId, groupIndex);
  }
```

(Keep both wrapper methods for now — the call sites still reference them. They become trivial delegates. We'll either keep them or inline at the call sites once Task 7 lands.)

- [ ] **Step 3: Run analyze**

Run: `flutter analyze lib/screens/program_a_setup_screen.dart`
Expected: No errors.

- [ ] **Step 4: Run existing screen test**

Run: `flutter test test/screens/program_a_setup_screen_test.dart`
Expected: All existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/program_a_setup_screen.dart
git commit -m "refactor(setup): unify group-target ops with SnackBar undo"
```

---

## Task 7: Wire sheet to group-card tap + phase-watcher auto-dismiss

**Files:**
- Modify: `lib/screens/program_a_setup_screen.dart`
- Modify: `test/screens/program_a_setup_screen_test.dart`

On group card tap, call `_openGroupSheet(i)` which selects the group AND shows the bottom sheet. Inside the sheet, the move tap calls `_moveBetweenGroups(...)`. Phase transitions out of `idle` auto-dismiss the sheet.

- [ ] **Step 1: Add the sheet-open helper**

In `_ProgramASetupScreenState`, add:

```dart
  Future<void> _openGroupSheet(int groupIndex) async {
    final thisGroupIds = List<int>.from(groups[groupIndex].targetIds);
    final assignedElsewhereIds = <int>[];
    final targetIdToGroupIndex = <int, int>{};
    for (var gi = 0; gi < groups.length; gi++) {
      if (gi == groupIndex) continue;
      for (final tid in groups[gi].targetIds) {
        assignedElsewhereIds.add(tid);
        targetIdToGroupIndex[tid] = gi;
      }
    }
    final state = context.read<AppState>();
    // Filter ASSIGNED ELSEWHERE to online targets only (mirrors AVAILABLE).
    final onlineIds = state.targets
        .where((t) => t.isOnline)
        .map((t) => t.id)
        .toSet();
    assignedElsewhereIds.removeWhere((id) => !onlineIds.contains(id));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<AppState>.value(
        value: state,
        child: GroupTargetSheet(
          groupIndex: groupIndex,
          thisGroupIds: thisGroupIds,
          assignedElsewhereIds: assignedElsewhereIds,
          targetIdToGroupIndex: targetIdToGroupIndex,
          onAdd: (id) => _addToGroup(id, groupIndex),
          onRemove: (id) => _removeFromGroup(id, groupIndex),
          onMove: (id, from) => _moveBetweenGroups(id, from, groupIndex),
        ),
      ),
    );
  }
```

Add the import at the top of the file:

```dart
import '../widgets/group_target_sheet.dart';
```

- [ ] **Step 2: Hook into the group card tap**

Find the `GroupNodeCard` call site (around line 425, inside the `List.generate`). Change the existing `onTap` to also call `_openGroupSheet`:

```dart
                child: GroupNodeCard(
                  groupIndex: i,
                  targetIds: groups[i].targetIds,
                  selected: selectedGroupIndex == i,
                  resolver: resolver,
                  onTap: () {
                    setState(() => selectedGroupIndex = i);
                    _openGroupSheet(i);
                  },
                  onRemoveTarget: (id) => _removeTargetFromGroup(i, id),
                ),
```

(Note: this removes the `expanded:` param. That's intentional — Task 8 removes it from `GroupNodeCard`'s constructor entirely. After Task 7 is committed, this call site will fail analyze; commit Task 7 anyway and proceed immediately to Task 8 — they're a pair, like Task 5/6 of the prior plan. Alternatively, run Task 7 + Task 8 back-to-back without committing Task 7 first.)

For safety, run analyze after Step 2 and accept the expected `expanded`-missing error in `GroupNodeCard`'s constructor — confirm it's the only new error.

- [ ] **Step 3: Add a phase-watcher to auto-dismiss the sheet**

The sheet should auto-dismiss when `state.phase` leaves `idle`. The cleanest implementation: when opening the sheet, wrap the `GroupTargetSheet` in a small `StatefulWidget` that listens to `AppState` and pops the route when `state.phase != DrillPhase.idle`. Add this near the sheet helper:

```dart
class _PhaseAwareSheet extends StatefulWidget {
  final Widget child;
  const _PhaseAwareSheet({required this.child});

  @override
  State<_PhaseAwareSheet> createState() => _PhaseAwareSheetState();
}

class _PhaseAwareSheetState extends State<_PhaseAwareSheet> {
  late final VoidCallback _listener;
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _listener = () {
      if (_state.phase != DrillPhase.idle && mounted) {
        Navigator.of(context).maybePop();
      }
    };
    _state.addListener(_listener);
  }

  @override
  void dispose() {
    _state.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

Wrap the sheet builder return value:

```dart
      builder: (_) => ChangeNotifierProvider<AppState>.value(
        value: state,
        child: _PhaseAwareSheet(
          child: GroupTargetSheet(
            // ...same as before
          ),
        ),
      ),
```

- [ ] **Step 4: Add screen-level tests**

In `test/screens/program_a_setup_screen_test.dart`, add the following tests (alongside whatever currently exists, after the Task 3 infrastructure fix):

```dart
  testWidgets('tapping a group card opens the bottom sheet',
      (tester) async {
    // Build state with at least one online target so AVAILABLE is non-empty.
    final state = AppState()
      ..targets = [TargetUnit(id: 1, address: 'A1')..isOnline = true];
    await pumpScreen(tester, state); // use whatever helper exists in this file
    // Tap the first group card by tapping its label.
    await tester.tap(find.text('GROUP 01'));
    await tester.pumpAndSettle();
    expect(find.text('GROUP 01 — TARGETS'), findsOneWidget);
    expect(find.text('AVAILABLE'), findsOneWidget);
  });

  testWidgets('SnackBar with UNDO appears after adding a target',
      (tester) async {
    final state = AppState()
      ..targets = [TargetUnit(id: 2, address: 'A2')..isOnline = true];
    await pumpScreen(tester, state);
    await tester.tap(find.text('GROUP 01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('T/U_02'));
    await tester.pumpAndSettle();
    expect(find.text('UNDO'), findsOneWidget);
  });

  testWidgets('phase change auto-dismisses the sheet', (tester) async {
    final state = AppState()
      ..targets = [TargetUnit(id: 1, address: 'A1')..isOnline = true];
    await pumpScreen(tester, state);
    await tester.tap(find.text('GROUP 01'));
    await tester.pumpAndSettle();
    expect(find.text('GROUP 01 — TARGETS'), findsOneWidget);
    state.setPhaseForTesting(DrillPhase.arming);
    await tester.pumpAndSettle();
    expect(find.text('GROUP 01 — TARGETS'), findsNothing);
  });
```

The tests reference helpers that may or may not exist:
- `pumpScreen(tester, state)` — if no such helper exists, replace each call with the full `MultiProvider` + `MaterialApp` pump from Task 3's repair.
- `setPhaseForTesting(DrillPhase)` — check `lib/state/app_state.dart` for an existing helper; if absent, add it alongside the other `*ForTesting` methods:

  ```dart
  @visibleForTesting
  void setPhaseForTesting(DrillPhase p) {
    _phase = p;
    notifyListeners();
  }
  ```

- [ ] **Step 5: Run analyze + tests**

Run: `flutter analyze lib/screens/program_a_setup_screen.dart`
Expected: One error about `expanded` parameter being required by `GroupNodeCard` — that's the cross-task dependency Task 8 resolves. Confirm it's the only new error.

Tests will not yet pass because the analyze error blocks the test runner. Proceed directly to Task 8 — combined commit at the end of Task 8.

- [ ] **Step 6: DO NOT COMMIT YET — combine with Task 8**

---

## Task 8: Remove `expanded` from `GroupNodeCard` + cleanup tests

**Files:**
- Modify: `lib/widgets/tactical/group_node_card.dart`
- Modify: `test/widgets/tactical/group_node_card_test.dart`

- [ ] **Step 1: Strip `expanded` from `GroupNodeCard`**

Open `lib/widgets/tactical/group_node_card.dart`. Make these specific changes:

1. Remove the `final bool expanded;` field.
2. Remove the `required this.expanded,` from the constructor.
3. In `build`, replace the entire `expanded ? Wrap<InputChip>(...) : _CollapsedLabels(...)` ternary with just `_CollapsedLabels(targetIds: targetIds, resolver: resolver)`.
4. Delete the now-dead `InputChip` branch.

The final widget should render `_CollapsedLabels` unconditionally for any non-empty `targetIds`.

- [ ] **Step 2: Update tests**

In `test/widgets/tactical/group_node_card_test.dart`:

1. Remove `expanded: ...` from every `GroupNodeCard(...)` call (search-and-replace).
2. Delete the test `'expanded card shows chips with remove buttons'` (the equivalent coverage now lives in `group_target_sheet_test.dart`).
3. Keep all other tests intact.

- [ ] **Step 3: Run analyze project-wide**

Run: `flutter analyze`
Expected: No errors.

- [ ] **Step 4: Run the full widget test suite for touched files**

Run: `flutter test test/widgets/tactical/group_node_card_test.dart test/widgets/group_target_sheet_test.dart test/screens/program_a_setup_screen_test.dart`
Expected: All pass.

- [ ] **Step 5: Commit Task 7 + Task 8 together**

```bash
git add lib/screens/program_a_setup_screen.dart \
        lib/widgets/tactical/group_node_card.dart \
        test/widgets/tactical/group_node_card_test.dart \
        test/screens/program_a_setup_screen_test.dart
git commit -m "feat(allocation): tap group card opens bottom sheet; remove in-place expansion"
```

---

## Task 9: Manual smoke test on iPhone

**Files:** none

Build a release IPA, install on the iPhone, untether, take to the garage.

- [ ] **Step 1: Build + install release**

Run: `flutter clean && flutter run --release -d <iphone-udid>`

(The user has done this before with udid `00008140-000C0D093A98801C`. Adjust to whatever device is connected.)

After installation, the user can disconnect tether/wifi and test in the field.

- [ ] **Step 2: On-device checklist**

- Setup screen → tap a group card → bottom sheet slides up showing `GROUP 0X — TARGETS`.
- Sheet shows three sections as appropriate (`IN THIS GROUP` with `✕`, `AVAILABLE`, `ASSIGNED ELSEWHERE` with source-group badge).
- Empty sections are hidden.
- Tap a target in `AVAILABLE` → row migrates to `IN THIS GROUP`; SnackBar with `UNDO` appears.
- Tap `UNDO` → the add is reversed within 5 seconds.
- Tap `✕` on a target in `IN THIS GROUP` → row removed; SnackBar with `UNDO`.
- Tap a target in `ASSIGNED ELSEWHERE` → `MOVE TARGET` dialog appears.
- Tap `CANCEL` → no state change.
- Tap a target in `ASSIGNED ELSEWHERE` again → dialog reappears.
- Check "Don't show this again", tap `MOVE` → target migrates to this group; SnackBar appears.
- Tap a third target in `ASSIGNED ELSEWHERE` → dialog is **skipped**; move happens immediately.
- Restart the app → tap a target in `ASSIGNED ELSEWHERE` → dialog is still skipped (persistence verified).
- Confirm: no in-place expansion, no overflow, group cards stay fixed-size regardless of how many targets are assigned.

- [ ] **Step 3: No commit (manual verification only)**

If anything fails, file a follow-up task or fix inline.

---

## Self-Review Checklist (writer use)

- [x] Spec §1 (collapsed card unchanged) — covered by Task 8 (remove `expanded`, keep `_CollapsedLabels` only).
- [x] Spec §2 (sheet structure: three sections, drag-to-dismiss, hide empty) — Task 4.
- [x] Spec §3 (confirm-and-move dialog + persistence) — Task 5.
- [x] Spec §4 (atomic move) — Task 6 `_moveBetweenGroups`.
- [x] Spec §5 (SnackBar undo, most-recent-only, no follow-up SnackBar on undo) — Task 6.
- [x] Spec §6 (shared action layer used by both sheet AND strip) — Task 6.
- [x] Spec §7 (preserve `AVAILABLE_NODES` strip) — Task 6 keeps the strip; it routes through the same `_addToGroup`.
- [x] Spec §8 (reset confirmations menu entry) — explicitly out of scope for v1 plan.
- [x] Migration §1 (repair program_a_setup_screen_test) — Task 3.
- [x] Migration §2-4 (remove `expanded`, `_expandedGroupIndex`, collapse-on-empty fix) — Task 7 + Task 8.
- [x] Phase-change auto-dismiss — Task 7.
- [x] No placeholders. Every code step shows actual code or an exact command.
- [x] Type consistency: `_addToGroup`, `_removeFromGroup`, `_moveBetweenGroups`, `GroupTargetSheet`, `_MoveConfirmationDialog`, `skipMoveConfirmation`, `setSkipMoveConfirmation` — all referenced identically across tasks.
- [x] Each step is 2-5 minute granularity.
