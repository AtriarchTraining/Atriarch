# Unit Labels & Card Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the default target-unit label from `T#` / `NODE_T#` to `T/U_##`, make post-drill `PER_NODE` rows expandable to show that unit's events, and convert group cards in the allocation grid to fixed-size collapsed cards that expand on tap to allow target removal.

**Architecture:** All three changes are UI-layer. The default-label change centralizes in [lib/util/target_name_resolver.dart](lib/util/target_name_resolver.dart) (already exists with a `T{id}` fallback) — we update its fallback and route the remaining hardcoded `T$id` / `NODE_T$id` / `Target $id` strings through it. Expansion state is local widget state in `_ResultsScreenState` (new) and `_ProgramASetupScreenState` (new field).

**Tech Stack:** Flutter / Dart, Provider for app state, existing `TargetNameResolver` util, existing tactical widget library.

**Spec:** [docs/superpowers/specs/2026-04-30-unit-labels-and-card-expansion-design.md](docs/superpowers/specs/2026-04-30-unit-labels-and-card-expansion-design.md)

---

## File Map

**Modify:**
- [lib/util/target_name_resolver.dart](lib/util/target_name_resolver.dart) — change default fallback from `T$id` → `T/U_##`.
- [lib/screens/results_screen.dart](lib/screens/results_screen.dart) — convert `StatelessWidget` → `StatefulWidget`; route `_PerTargetRow` and `_EventRow` through the resolver; add single-row expand state.
- [lib/widgets/tactical/group_node_card.dart](lib/widgets/tactical/group_node_card.dart) — accept a `TargetNameResolver`, render unit labels (no `✕`) in collapsed state, render unit chips with `✕` in expanded state, fixed collapsed height.
- [lib/screens/program_a_setup_screen.dart](lib/screens/program_a_setup_screen.dart) — track expanded group index; pass `expanded` + resolver to `GroupNodeCard`.
- [lib/screens/session_detail_screen.dart](lib/screens/session_detail_screen.dart) — replace hardcoded `NODE_T$id` with resolver display.
- [lib/screens/target_breakdown_screen.dart](lib/screens/target_breakdown_screen.dart) — replace hardcoded `NODE_T$id` with resolver display.

**Test:**
- [test/util/target_name_resolver_test.dart](test/util/target_name_resolver_test.dart) — new file; covers fallback format and custom-name override.
- [test/widgets/group_node_card_test.dart](test/widgets/group_node_card_test.dart) — new file; covers collapsed rendering, expansion, single-expand at the parent level, target remove tap.
- [test/screens/results_screen_per_node_expand_test.dart](test/screens/results_screen_per_node_expand_test.dart) — new file; covers single-row expand and event filtering.

**Do NOT touch:**
- Group / controller-node header label `NODE_${groupIndex+1}` in [lib/widgets/tactical/group_node_card.dart](lib/widgets/tactical/group_node_card.dart) — this is the group label, not a target-unit label.
- Decorative `NODE_SCAN` and `NODE_ACTIONS` strings in [lib/screens/program_b_setup_screen.dart:289](lib/screens/program_b_setup_screen.dart#L289) and [lib/widgets/target_actions_sheet.dart:67](lib/widgets/target_actions_sheet.dart#L67) — these are section trailers, not unit labels.
- Database schema, BLE protocol, event types.

---

## Task 1: Update `TargetNameResolver` default label format

**Files:**
- Test: `test/util/target_name_resolver_test.dart` (create)
- Modify: `lib/util/target_name_resolver.dart`

The current resolver returns `T$id` when no custom name is set. We change the fallback to `T/U_##` (zero-padded two digits). Custom names are unchanged.

- [ ] **Step 1: Write the failing tests**

Create `test/util/target_name_resolver_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/util/target_name_resolver.dart';

void main() {
  group('TargetNameResolver.display', () {
    test('returns custom name when present', () {
      const resolver = TargetNameResolver({1: 'Flipper', 2: 'Popper'});
      expect(resolver.display(1), 'Flipper');
      expect(resolver.display(2), 'Popper');
    });

    test('returns T/U_## fallback with zero-padding for ids 1-9', () {
      const resolver = TargetNameResolver({});
      expect(resolver.display(1), 'T/U_01');
      expect(resolver.display(7), 'T/U_07');
      expect(resolver.display(9), 'T/U_09');
    });

    test('returns T/U_## fallback for two-digit ids', () {
      const resolver = TargetNameResolver({});
      expect(resolver.display(10), 'T/U_10');
      expect(resolver.display(42), 'T/U_42');
    });

    test('falls back when only some ids have custom names', () {
      const resolver = TargetNameResolver({1: 'Flipper'});
      expect(resolver.display(1), 'Flipper');
      expect(resolver.display(2), 'T/U_02');
    });

    test('customName returns the stored custom name or null', () {
      const resolver = TargetNameResolver({1: 'Flipper'});
      expect(resolver.customName(1), 'Flipper');
      expect(resolver.customName(2), isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/util/target_name_resolver_test.dart`
Expected: 5 tests, fallback tests FAIL with `Expected: 'T/U_01' Actual: 'T1'`. Custom-name and `customName` tests PASS.

- [ ] **Step 3: Update the resolver**

Replace the body of `lib/util/target_name_resolver.dart`:

```dart
/// Resolves a target id to its user-facing display name.
///
/// Stateless helper built from a snapshot of the saved names map
/// (see [PreferencesRepository.getTargetNames]). `AppState` exposes a live
/// resolver; consumers that render chips / tables / event logs should use
/// [display] instead of hard-coding `'T{id}'` or `'NODE_T{id}'`.
class TargetNameResolver {
  final Map<int, String> names;

  const TargetNameResolver(this.names);

  /// Display name: the custom name when saved, else `T/U_##` fallback
  /// (zero-padded two-digit unit number).
  String display(int targetId) =>
      names[targetId] ?? 'T/U_${targetId.toString().padLeft(2, '0')}';

  /// The stored custom name, or null when none is saved.
  String? customName(int targetId) => names[targetId];
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/util/target_name_resolver_test.dart`
Expected: All 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/util/target_name_resolver.dart test/util/target_name_resolver_test.dart
git commit -m "refactor(target-labels): default display T/U_## with zero pad"
```

---

## Task 2: Route results screen labels through the resolver

**Files:**
- Modify: `lib/screens/results_screen.dart`

The results screen hardcodes `NODE_T$id` (PER_NODE rows) and `Target ${event.targetId}` (event log rows). We route both through `TargetNameResolver` so they pick up the new `T/U_##` default and respect custom names.

- [ ] **Step 1: Add resolver wiring at the top of `build`**

In `lib/screens/results_screen.dart`, find the `build` method (currently around line 22). Below the existing `final state = context.watch<AppState>();` line, add:

```dart
    final resolver = TargetNameResolver(state.targetNames);
```

Add the import at the top of the file with the other relative imports:

```dart
import '../util/target_name_resolver.dart';
```

- [ ] **Step 2: Pass the resolver into `_PerTargetRow` and `_EventRow`**

Update `_PerTargetRow` (currently around line 243):

```dart
class _PerTargetRow extends StatelessWidget {
  final int id;
  final _TargetStats stats;
  final TargetNameResolver resolver;
  const _PerTargetRow({
    required this.id,
    required this.stats,
    required this.resolver,
  });
```

Replace the hardcoded label inside the `Text` widget (currently `'NODE_T$id'` near line 258):

```dart
            child: Text(
              resolver.display(id),
              style: AtriarchText.labelTiny(color: tokens.statusHit),
            ),
```

Note: the surrounding `SizedBox(width: 72, ...)` may need to be widened to fit longer custom names. Change to `width: 96`.

Update `_EventRow` (currently around line 317):

```dart
class _EventRow extends StatelessWidget {
  final SessionEvent event;
  final TargetNameResolver resolver;
  const _EventRow({required this.event, required this.resolver});
```

Inside the `switch` expression in `_EventRow.build`, replace each `'Target ${event.targetId}'` substring with `resolver.display(event.targetId!)`. The full updated switch:

```dart
    final id = event.targetId;
    final label = id != null ? resolver.display(id) : '';
    final (color, text) = switch (event.type) {
      EventType.targetActivated => (
          tokens.statusLive,
          '$label activated',
        ),
      EventType.hitDetected => (
          tokens.statusHit,
          '$label hit ${event.hitNumber}/${event.requiredHits}',
        ),
      EventType.targetComplete => (
          tokens.statusLive,
          '$label complete (${event.totalTimeMs}ms)',
        ),
      EventType.noShootViolation => (
          tokens.statusViolation,
          'NO-SHOOT $label!',
        ),
      EventType.lateHit => (
          tokens.statusLate,
          'Late hit on $label',
        ),
      EventType.drillFinished => (tokens.textTertiary, 'Drill finished'),
      EventType.error => (
          tokens.statusViolation,
          'Error: ${event.errorDetail}',
        ),
    };
```

- [ ] **Step 3: Pass `resolver` from `build` to the row constructors**

Update the `_PerTargetRow` construction site (currently around line 127):

```dart
              child: _PerTargetRow(
                id: entry.key,
                stats: entry.value,
                resolver: resolver,
              ),
```

Update the `_EventRow` construction site (currently around line 170):

```dart
          ...events.map((e) => _EventRow(event: e, resolver: resolver)),
```

- [ ] **Step 4: Run flutter analyze**

Run: `flutter analyze lib/screens/results_screen.dart`
Expected: No errors. (Warnings unrelated to this change are acceptable.)

- [ ] **Step 5: Run the existing widget test suite for the results screen if any, plus the resolver tests**

Run: `flutter test test/util/target_name_resolver_test.dart`
Expected: PASS.

If a `test/screens/results_screen_test.dart` exists, run it too and update any expectations referencing `NODE_T$id` or `Target $id` strings to use the new `T/U_##` format.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/results_screen.dart
git commit -m "feat(results): route PER_NODE and EVENT_LOG labels through resolver"
```

---

## Task 3: Update session detail and target breakdown labels

**Files:**
- Modify: `lib/screens/session_detail_screen.dart`
- Modify: `lib/screens/target_breakdown_screen.dart`

These two screens also hardcode `NODE_T$id`. Route them through the resolver.

- [ ] **Step 1: Update `session_detail_screen.dart`**

Find line ~255: `'NODE_T${e.targetId}',`.

Add the import at the top of the file (next to existing `../util/...` imports):

```dart
import '../util/target_name_resolver.dart';
```

Inside the `build` method, near the top where state is read, add:

```dart
    final resolver = TargetNameResolver(
      Provider.of<AppState>(context, listen: false).targetNames,
    );
```

(Adjust to match the file's existing pattern for reading `AppState` — if it already calls `context.watch<AppState>()` or `Consumer<AppState>`, reuse that and add `final resolver = TargetNameResolver(state.targetNames);` next to it.)

Replace `'NODE_T${e.targetId}'` with `resolver.display(e.targetId!)`. If `e.targetId` is non-nullable here (depends on the surrounding type), use `resolver.display(e.targetId)`.

- [ ] **Step 2: Update `target_breakdown_screen.dart`**

Find line ~117: `'NODE_T${b.targetId}',`.

Add the resolver import and instantiate it the same way as Step 1. Replace the hardcoded string with `resolver.display(b.targetId)`.

- [ ] **Step 3: Run flutter analyze**

Run: `flutter analyze lib/screens/session_detail_screen.dart lib/screens/target_breakdown_screen.dart`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/session_detail_screen.dart lib/screens/target_breakdown_screen.dart
git commit -m "refactor(labels): route session-detail and breakdown through resolver"
```

---

## Task 4: Add `PER_NODE` row expansion to results screen

**Files:**
- Modify: `lib/screens/results_screen.dart`
- Test: `test/screens/results_screen_per_node_expand_test.dart` (create)

Convert `ResultsScreen` from `StatelessWidget` to `StatefulWidget`. Add an `int? _expandedTargetId` field. Tapping a `_PerTargetRow` toggles it. When expanded, render that target's events inline beneath the row.

- [ ] **Step 1: Write the failing widget test**

Create `test/screens/results_screen_per_node_expand_test.dart`:

```dart
import 'package:atriarch/models/drill_session.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/screens/results_screen.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_app_state.dart'; // see note below

void main() {
  testWidgets('PER_NODE row expands to show that unit\'s events', (tester) async {
    final start = DateTime(2026, 4, 30, 10, 0, 0);
    final session = DrillSession(
      id: 'test',
      templateId: 'template',
      startedAt: start,
      endedAt: start.add(const Duration(seconds: 30)),
      events: [
        SessionEvent(
          type: EventType.targetActivated,
          targetId: 1,
          timestamp: start,
        ),
        SessionEvent(
          type: EventType.hitDetected,
          targetId: 1,
          hitNumber: 1,
          requiredHits: 1,
          timestamp: start.add(const Duration(seconds: 1)),
        ),
        SessionEvent(
          type: EventType.targetComplete,
          targetId: 1,
          totalTimeMs: 1000,
          timestamp: start.add(const Duration(seconds: 1)),
        ),
        SessionEvent(
          type: EventType.targetActivated,
          targetId: 2,
          timestamp: start.add(const Duration(seconds: 2)),
        ),
      ],
    );

    final state = FakeAppState(session: session);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: AtriarchTheme(child: const MaterialApp(home: ResultsScreen())),
      ),
    );

    // Both rows are visible in the PER_NODE section.
    expect(find.text('T/U_01'), findsOneWidget);
    expect(find.text('T/U_02'), findsOneWidget);

    // Tap the T/U_01 row.
    await tester.tap(find.text('T/U_01'));
    await tester.pumpAndSettle();

    // Inline events for T/U_01 are visible (the strings appear twice now —
    // once in the inline expansion and once in the global EVENT_LOG below).
    expect(find.textContaining('T/U_01 activated'), findsNWidgets(2));
    expect(find.textContaining('T/U_01 hit 1/1'), findsNWidgets(2));
    expect(find.textContaining('T/U_01 complete'), findsNWidgets(2));

    // T/U_02's only event ("activated") appears just once — in the global log,
    // not inside the T/U_01 expansion.
    expect(find.textContaining('T/U_02 activated'), findsOneWidget);
  });

  testWidgets('Expanding a second PER_NODE row collapses the first',
      (tester) async {
    // Build the same session as above, expand T/U_01, then tap T/U_02
    // and assert T/U_01's inline events are no longer rendered (count
    // returns to 1 — only the global log entry).
    // ... (mirror first test's setup, then: tap T/U_01, pump,
    //      tap T/U_02, pump, expect T/U_01 inline gone)
  });
}
```

If `test/test_helpers/fake_app_state.dart` does not yet exist with a constructor that accepts `session`, create a minimal one that overrides `currentSession`, `currentMetrics`, and `targetNames`. Look at any existing fake under `test/test_helpers/` for the pattern.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/screens/results_screen_per_node_expand_test.dart`
Expected: FAIL — `T/U_01` row is not tappable, expansion doesn't render.

- [ ] **Step 3: Convert `ResultsScreen` to `StatefulWidget`**

Replace the class declaration in `lib/screens/results_screen.dart`:

```dart
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  int? _expandedTargetId;

  @override
  Widget build(BuildContext context) {
    // ... (existing build body)
```

Move the existing `build` body into `_ResultsScreenState.build`. The `_openShareSheet` and `_formatDuration` methods move to `_ResultsScreenState` as well.

- [ ] **Step 4: Wire expand state into `_PerTargetRow`**

Update `_PerTargetRow` to accept tap and expanded flag:

```dart
class _PerTargetRow extends StatelessWidget {
  final int id;
  final _TargetStats stats;
  final TargetNameResolver resolver;
  final bool expanded;
  final VoidCallback onTap;
  final List<SessionEvent> events;
  const _PerTargetRow({
    required this.id,
    required this.stats,
    required this.resolver,
    required this.expanded,
    required this.onTap,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTap,
          child: TacticalCard(
            accent: tokens.border,
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    resolver.display(id),
                    style: AtriarchText.labelTiny(color: tokens.statusHit),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _kv('HITS', '${stats.hits}', tokens),
                        _kv('DONE', '${stats.completions}', tokens),
                        _kv('AVG', '${stats.avgCompletionMs.toInt()}MS', tokens),
                        _kv(
                          'NS',
                          '${stats.noShoots}',
                          tokens,
                          color: stats.noShoots > 0
                              ? tokens.statusViolation
                              : tokens.textPrimary,
                        ),
                        _kv(
                          'LATE',
                          '${stats.lateHits}',
                          tokens,
                          color: stats.lateHits > 0
                              ? tokens.statusLate
                              : tokens.textPrimary,
                        ),
                      ],
                    ),
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: tokens.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(
              left: AtriarchSpacing.lg,
              top: AtriarchSpacing.sm,
              bottom: AtriarchSpacing.sm,
            ),
            child: Column(
              children: events
                  .map((e) => _EventRow(event: e, resolver: resolver))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _kv(String k, String v, AtriarchTokens tokens, {Color? color}) {
    // unchanged
  }
}
```

- [ ] **Step 5: Wire expand state from `_ResultsScreenState`**

In `_ResultsScreenState.build`, replace the `_PerTargetRow` construction site:

```dart
          ...perTarget.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: AtriarchSpacing.sm),
              child: _PerTargetRow(
                id: entry.key,
                stats: entry.value,
                resolver: resolver,
                expanded: _expandedTargetId == entry.key,
                onTap: () => setState(() {
                  _expandedTargetId =
                      _expandedTargetId == entry.key ? null : entry.key;
                }),
                events: events
                    .where((e) => e.targetId == entry.key)
                    .toList(),
              ),
            ),
          ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/screens/results_screen_per_node_expand_test.dart`
Expected: Both tests PASS.

- [ ] **Step 7: Run flutter analyze**

Run: `flutter analyze lib/screens/results_screen.dart`
Expected: No errors.

- [ ] **Step 8: Commit**

```bash
git add lib/screens/results_screen.dart test/screens/results_screen_per_node_expand_test.dart
git commit -m "feat(results): expandable PER_NODE rows with inline event filter"
```

---

## Task 5: Group card collapsed/expanded redesign

**Files:**
- Modify: `lib/widgets/tactical/group_node_card.dart`
- Test: `test/widgets/group_node_card_test.dart` (create)

`GroupNodeCard` becomes a fixed-size card in collapsed state, showing only target-unit labels (no `✕`). It accepts an `expanded` bool and a `TargetNameResolver`. When `expanded`, it renders chips with `✕` remove buttons. The parent (`program_a_setup_screen`) owns the expand state.

- [ ] **Step 1: Write the failing widget tests**

Create `test/widgets/group_node_card_test.dart`:

```dart
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/util/target_name_resolver.dart';
import 'package:atriarch/widgets/tactical/group_node_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget _wrap(Widget child) =>
      AtriarchTheme(child: MaterialApp(home: Scaffold(body: child)));

  testWidgets('collapsed card shows unit labels and no remove buttons',
      (tester) async {
    await tester.pumpWidget(_wrap(GroupNodeCard(
      groupIndex: 0,
      targetIds: const [1, 2],
      selected: false,
      expanded: false,
      resolver: const TargetNameResolver({}),
      onTap: () {},
      onRemoveTarget: (_) {},
    )));

    expect(find.text('T/U_01'), findsOneWidget);
    expect(find.text('T/U_02'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('expanded card shows chips with remove buttons',
      (tester) async {
    int? removed;
    await tester.pumpWidget(_wrap(GroupNodeCard(
      groupIndex: 0,
      targetIds: const [1, 2],
      selected: false,
      expanded: true,
      resolver: const TargetNameResolver({}),
      onTap: () {},
      onRemoveTarget: (id) => removed = id,
    )));

    expect(find.text('T/U_01'), findsOneWidget);
    expect(find.text('T/U_02'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.close).first);
    expect(removed, 1);
  });

  testWidgets('tap on collapsed card invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(GroupNodeCard(
      groupIndex: 0,
      targetIds: const [1],
      selected: false,
      expanded: false,
      resolver: const TargetNameResolver({}),
      onTap: () => tapped = true,
      onRemoveTarget: (_) {},
    )));

    await tester.tap(find.byType(GroupNodeCard));
    expect(tapped, true);
  });

  testWidgets('uses custom name when resolver provides one', (tester) async {
    await tester.pumpWidget(_wrap(GroupNodeCard(
      groupIndex: 0,
      targetIds: const [1, 2],
      selected: false,
      expanded: false,
      resolver: const TargetNameResolver({1: 'Flipper'}),
      onTap: () {},
      onRemoveTarget: (_) {},
    )));

    expect(find.text('Flipper'), findsOneWidget);
    expect(find.text('T/U_02'), findsOneWidget);
    expect(find.text('T/U_01'), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/group_node_card_test.dart`
Expected: FAIL — `expanded` and `resolver` parameters don't exist on `GroupNodeCard`.

- [ ] **Step 3: Update `GroupNodeCard`**

Replace `lib/widgets/tactical/group_node_card.dart`:

```dart
import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';
import '../../util/target_name_resolver.dart';

class GroupNodeCard extends StatelessWidget {
  final int groupIndex; // 0-based
  final List<int> targetIds;
  final bool selected;
  final bool expanded;
  final TargetNameResolver resolver;
  final VoidCallback onTap;
  final ValueChanged<int> onRemoveTarget;

  const GroupNodeCard({
    super.key,
    required this.groupIndex,
    required this.targetIds,
    required this.selected,
    required this.expanded,
    required this.resolver,
    required this.onTap,
    required this.onRemoveTarget,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final assigned = targetIds.isNotEmpty;
    final groupColor = tokens.groupColor(groupIndex + 1);
    final nodeLabel =
        'NODE_${(groupIndex + 1).toString().padLeft(2, '0')}';
    final groupLabel = 'GROUP ${(groupIndex + 1).toString().padLeft(2, '0')}';

    final bg = assigned
        ? tokens.bgElevated
        : tokens.bgCard.withValues(alpha: 0.5);
    final border = selected
        ? Border.all(color: tokens.statusHit, width: 2)
        : Border(
            left: BorderSide(
              color: assigned
                  ? groupColor
                  : tokens.border.withValues(alpha: 0.2),
              width: 2,
            ),
          );

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: border),
          padding: const EdgeInsets.all(AtriarchSpacing.md),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nodeLabel,
                    style: AtriarchText.labelTiny(
                      color: assigned
                          ? groupColor
                          : tokens.textTertiary.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    groupLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: assigned
                              ? tokens.textPrimary
                              : tokens.textTertiary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AtriarchSpacing.md),
                  if (targetIds.isNotEmpty)
                    expanded
                        ? Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: targetIds
                                .map(
                                  (id) => InputChip(
                                    label: Text(resolver.display(id)),
                                    onDeleted: () => onRemoveTarget(id),
                                    deleteIcon: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: tokens.statusViolation,
                                    ),
                                  ),
                                )
                                .toList(),
                          )
                        : Wrap(
                            spacing: AtriarchSpacing.sm,
                            runSpacing: 4,
                            children: targetIds
                                .map(
                                  (id) => Text(
                                    resolver.display(id),
                                    style: AtriarchText.labelTiny(
                                      color: tokens.textPrimary,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  const SizedBox(height: AtriarchSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        assigned ? 'ASSIGNED' : 'STANDBY',
                        style: AtriarchText.labelTiny(
                          color: tokens.textTertiary,
                        ),
                      ),
                      Container(
                        width: 24,
                        height: 3,
                        color: assigned
                            ? groupColor
                            : tokens.border.withValues(alpha: 0.3),
                      ),
                    ],
                  ),
                ],
              ),
              if (assigned)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.check_circle,
                    size: 14,
                    color: groupColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the widget tests to verify they pass**

Run: `flutter test test/widgets/group_node_card_test.dart`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit (call sites still broken — fixed in Task 6)**

Skip this commit step — combine with Task 6 because the `expanded` and `resolver` params are now required and `program_a_setup_screen.dart` won't compile until updated.

---

## Task 6: Wire group card expansion in program A setup screen

**Files:**
- Modify: `lib/screens/program_a_setup_screen.dart`

The setup screen owns expand state via a single `int? _expandedGroupIndex` field, ensuring single-expand semantics across the grid. It also constructs and passes the `TargetNameResolver`.

- [ ] **Step 1: Add expand state field and resolver in build**

Find `_ProgramASetupScreenState` (the `State` class in `program_a_setup_screen.dart`). Add a field near the top of the state class:

```dart
  int? _expandedGroupIndex;
```

`build` already creates a resolver around line 262: `final resolver = TargetNameResolver(state.targetNames);` — confirm this is in scope where `GroupNodeCard` is constructed (around line 425). If the existing resolver is declared inside a different builder than the GridView, hoist it up so it's accessible at the GroupNodeCard call site, OR re-declare a local one in that scope.

- [ ] **Step 2: Pass `expanded` and `resolver` into `GroupNodeCard`**

Replace the `GroupNodeCard` construction (currently around line 425):

```dart
                child: GroupNodeCard(
                  groupIndex: i,
                  targetIds: groups[i].targetIds,
                  selected: selectedGroupIndex == i,
                  expanded: _expandedGroupIndex == i,
                  resolver: resolver,
                  onTap: () => setState(() {
                    selectedGroupIndex = i;
                    _expandedGroupIndex =
                        _expandedGroupIndex == i ? null : i;
                  }),
                  onRemoveTarget: (id) => _removeTargetFromGroup(i, id),
                ),
```

This makes tap toggle expansion (and select). At most one card is expanded at a time because `_expandedGroupIndex` is a single int.

- [ ] **Step 3: Run flutter analyze on the affected files**

Run: `flutter analyze lib/screens/program_a_setup_screen.dart lib/widgets/tactical/group_node_card.dart`
Expected: No errors.

- [ ] **Step 4: Run the full test suite to catch any regressions**

Run: `flutter test`
Expected: All tests PASS. If a pre-existing test in `test/screens/program_a_setup_screen*` (or similar) constructs `GroupNodeCard` directly and passes the old parameter set, update it to pass `expanded: false` and a `TargetNameResolver({})`.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/tactical/group_node_card.dart lib/screens/program_a_setup_screen.dart test/widgets/group_node_card_test.dart
git commit -m "feat(allocation): fixed-size group cards with tap-to-expand"
```

---

## Task 7: Manual smoke test on a connected device or simulator

**Files:** none

This is a sanity check. The unit/widget tests cover the logic; this catches visual regressions.

- [ ] **Step 1: Run the app**

Run: `flutter run -d <device>` (use whichever simulator or attached iPad you usually use for drill testing).

- [ ] **Step 2: Verify allocation grid (Program A setup)**

- Create / pick a drill template that uses Program A (multi-group).
- Assign 2-3 targets to one group, 1 target to another.
- Confirm: collapsed cards show `T/U_01 T/U_02` (no `✕`), card heights are uniform, no horizontal overflow.
- Tap a card with multiple targets. Confirm: card expands in place, chips with `✕` appear, other cards reflow below it.
- Tap a `✕`. Confirm: that target is removed from the group.
- Tap a different card. Confirm: the previously expanded card collapses.

- [ ] **Step 3: Verify post-drill results**

- Run a short drill (or use a saved session) so the results screen has data.
- Confirm: `PER_NODE` rows show `T/U_01`, `T/U_02`, etc.
- Confirm: `EVENT_LOG` entries say `T/U_01 activated`, `Late hit on T/U_01`, etc.
- Tap a `PER_NODE` row. Confirm: the row expands inline showing only that unit's events.
- Tap another row. Confirm: the first one collapses, the second expands.
- Tap the expanded row again. Confirm: it collapses.

- [ ] **Step 4: If a target has a custom name set, verify it overrides `T/U_##`**

- In any screen that supports renaming a target (long-press a `TargetNodeChip` to open `target_actions_sheet.dart`), set a custom name.
- Confirm: that name appears in group cards, allocation grid, results PER_NODE rows, and event log entries — instead of `T/U_##`.

- [ ] **Step 5: No commit (manual verification only)**

If anything fails the smoke test, file a follow-up by adding a failing test to the relevant test file and fixing inline. Otherwise the work is complete.

---

## Self-Review Checklist (writer use)

- [x] Task 1 covers spec §1 (label rename) at the resolver level.
- [x] Tasks 2 & 3 cover spec §1 surfaces: PER_NODE, EVENT_LOG, session detail, target breakdown.
- [x] Task 4 covers spec §2 (PER_NODE row expansion + single-expand).
- [x] Tasks 5 & 6 cover spec §3 (group card fixed size, tap-to-expand, single-expand, target remove).
- [x] Spec §1 "Out of scope" items (group/controller header `NODE_##`, `NODE_SCAN`, `NODE_ACTIONS`) explicitly listed in File Map "Do NOT touch".
- [x] No placeholders. Every step has actual code or an exact command.
- [x] Type consistency: `TargetNameResolver`, `_PerTargetRow`, `_EventRow`, and `GroupNodeCard` parameter names match across tasks.
- [x] Each step is 2-5 minute granularity.
