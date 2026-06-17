# Group Target Bottom Sheet — Design Spec

**Date:** 2026-05-11
**Status:** Approved (brainstorming)
**Scope:** Replace in-place group-card expansion with a bottom sheet that handles all target add/remove/move operations.

## Problem

The current allocation grid has two coupled issues:

1. **In-place expansion overflows.** Tapping a group card to expand reveals a `Wrap` of `InputChip` widgets. With 4+ chips at realistic grid widths (≈160px cells), the chips spill below the card's grid-cell bounds even after the recent collapsed-state fix. Spec §3 ("fixed-size collapsed cards") was satisfied; the expanded state never was. Manual testing on iPhone 26.4.2 confirms the overflow in production.
2. **No cross-group move affordance.** Moving a target from GROUP 03 to GROUP 04 today requires removing it from 03, then re-tapping the AVAILABLE_NODES chip after selecting 04. Two-step ritual, no confirmation, no undo.

## Goals

- Make the expanded chip view stop overflowing — by removing it entirely and moving target management into a bottom sheet.
- Add a first-class cross-group move flow with confirmation (suppressible) and undo.
- Preserve the existing fast bulk-assignment ergonomics for fresh-target assignment (tap-target-in-strip workflow).

## Non-Goals

- Redesigning the collapsed group card visual. The single-line bounded display shipped in commit `ca43336` stays.
- Renaming targets from the bottom sheet (custom names remain managed via `target_actions_sheet.dart`).
- Changing the BLE discovery / online-state model.
- Database schema changes (group assignments stay in-memory on `DrillConfig.groups` as today).

## Design

### 1. Collapsed group card (unchanged from `ca43336`)

The collapsed card stays as shipped: single-line bounded row of `T/U_##` labels separated by `·` with a trailing `…` when count exceeds `_kMaxVisible = 3`. The `expanded` parameter on `GroupNodeCard` is **removed**. The widget becomes purely a display + tap target.

**Removed code:**
- `bool expanded` parameter on `GroupNodeCard`.
- The `expanded ? Wrap<InputChip> : Wrap<Text>` ternary; only the collapsed branch (`_CollapsedLabels`) remains.
- `int? _expandedGroupIndex` field on `_ProgramASetupScreenState`.
- The `_expandedGroupIndex` clear inside `_removeTargetFromGroup` (collapse-on-empty defensive fix).
- All `expanded:` and `_expandedGroupIndex == i` references at call sites.

**Tap behavior:** tapping a group card sets `selectedGroupIndex = i` (existing behavior, preserves the magenta/cyan selection border) AND opens the bottom sheet for that group.

### 2. Bottom sheet — `GroupTargetSheet`

A new widget `lib/widgets/group_target_sheet.dart`, opened via `showModalBottomSheet`.

**Container:**
- Sheet at ~70% screen height with `isScrollControlled: true`, drag-to-dismiss enabled, tap-outside dismisses.
- Header: `GROUP NN — TARGETS` styled with `AtriarchText.titleMedium`, where `NN` is the zero-padded `groupIndex + 1`. A small drag handle above the header for affordance.
- Body is a `ListView` of three sections in fixed order; each section header uses `TacticalSection` (existing component) for visual consistency with the rest of the screen.

**Section 1 — `IN THIS GROUP`:**
- Trailing tag on the section header shows the active group label: `GROUP 04`.
- Row per target assigned to this group. Row layout: `T/U_##` (via `TargetNameResolver.display`) on the left, `Icons.close` button on the right.
- Tap the row → no-op (it's already in this group).
- Tap the `✕` → removes target from this group. Fires the shared `removeFromGroup` action (see §6); SnackBar with UNDO appears.
- If empty: hide the entire section (header + body).

**Section 2 — `AVAILABLE`:**
- Row per online, unassigned target. Layout: `T/U_##` on the left, no trailing element.
- Tap row → adds target to this group via shared `addToGroup` action; SnackBar with UNDO appears.
- If empty: hide the entire section.

**Section 3 — `ASSIGNED ELSEWHERE`:**
- Row per online target currently assigned to a **different** group. Layout: `T/U_##` on the left, a small `GROUP 0X` badge (using existing `tokens.groupColor(X)` for visual consistency) on the right.
- Tap row → opens confirm-and-move dialog (see §3), unless `skipMoveConfirmation` is set, in which case the move executes immediately.
- If empty: hide the entire section.

**Empty sheet state:** if all three sections are empty (no online targets at all), the sheet shows a single muted `'NO ONLINE TARGETS'` line below the header. The user can still dismiss.

**Sheet does not own state.** It reads `state.targets`, `groups[selectedGroupIndex].targetIds`, and `state.targetNames` reactively (rebuild via `context.watch<AppState>()`). Add/remove/move actions mutate `AppState` via the screen's existing handlers (see §6). When a target's group assignment changes, the sheet rebuilds, and the target visibly migrates between sections.

### 3. Confirm-and-move dialog

- Triggered only when tapping a target in `ASSIGNED ELSEWHERE` and `skipMoveConfirmation == false`.
- Implemented via `showDialog` over the sheet (the sheet stays mounted underneath).
- Title: `MOVE TARGET`
- Body: `Move T/U_03 from GROUP 03 to GROUP 04?` (with the actual resolved label and source/dest group numbers).
- A `CheckboxListTile` below the body: `Don't show this again` — default **unchecked**.
- Actions: `CANCEL` (closes dialog, no-op) and `MOVE` (closes dialog, executes the move).
- If the checkbox is checked AND `MOVE` is tapped: persist `skipMoveConfirmation = true` to shared_preferences via a new `PreferencesRepository` method (`setSkipMoveConfirmation` / `getSkipMoveConfirmation`). The flag is read at app start and exposed via `AppState.skipMoveConfirmation`.
- If only `CANCEL` is tapped, the checkbox state is discarded regardless.

### 4. Move execution + cross-group invariants

A move is logically a remove-from-source + add-to-destination. The shared action `moveBetweenGroups(targetId, fromGroupIndex, toGroupIndex)` (see §6) does both atomically inside a single `setState` so the UI never renders a transient "in neither group" state.

### 5. Undo — `SnackBar` with `UNDO` action

- After every `addToGroup`, `removeFromGroup`, or `moveBetweenGroups` action, show a `SnackBar` via the screen's `ScaffoldMessenger` with:
  - Message: `Target T/U_03 added to GROUP 04` / `Target T/U_03 removed from GROUP 04` / `Target T/U_03 moved from GROUP 03 to GROUP 04`.
  - Action: `UNDO`. Tapping it reverses the exact state change.
  - Duration: 5 seconds (Material default).
- "Most recent op only": each new SnackBar dismisses any previous one (via `hideCurrentSnackBar()` before `showSnackBar()`). Ops older than the most recent are not undoable.
- SnackBar attaches to the screen's scaffold, not the bottom sheet — it appears regardless of whether the sheet is still open.
- Undo logic mirror table:
  - Undo `add(t, g)` → `remove(t, g)` (no SnackBar follow-up).
  - Undo `remove(t, g)` → `add(t, g)` (no SnackBar follow-up).
  - Undo `move(t, gFrom, gTo)` → `move(t, gTo, gFrom)` (no SnackBar follow-up).
- Undo does **not** itself trigger another SnackBar — that would create infinite-undo confusion.

### 6. Shared action layer

To avoid two divergent assign paths (bottom sheet vs `AVAILABLE_NODES` strip), all target-assignment mutations go through a single set of methods on `_ProgramASetupScreenState`:

```dart
void _addToGroup(int targetId, int groupIndex);
void _removeFromGroup(int targetId, int groupIndex);
void _moveBetweenGroups(int targetId, int fromGroupIndex, int toGroupIndex);
```

Each method:
1. Mutates the in-memory `groups` list inside a `setState`.
2. Calls `_showUndoSnackBar(...)` with the appropriate message and inverse action.

Existing call sites (`_assignTargetToGroup` from the strip, `onRemoveTarget` from the card) are rewritten to delegate to `_addToGroup` / `_removeFromGroup`. The bottom sheet's tap handlers call the same methods directly. **One code path, one SnackBar, one undo.**

### 7. `AVAILABLE_NODES` strip — preserved

The `PARAM_04 AVAILABLE_NODES` strip below the group grid stays. It continues to show online targets not assigned to any group. Tap-strip-chip still adds to `selectedGroupIndex`'s group via `_addToGroup`. The bottom sheet and the strip both see the same `AppState` data and emit identical SnackBars.

When the user taps a target chip in the strip while no group is selected, the existing behavior (no-op or visual hint) is preserved — this spec does not change strip behavior beyond routing through the shared action.

### 8. Reset move confirmations (low-priority follow-up)

Add a `Reset move confirmations` entry to the existing 3-dot menu in `TacticalAppBar` on the Program A setup screen. Tapping it clears `skipMoveConfirmation` in shared_preferences and shows a confirmation toast. **This is explicitly scoped as a polish follow-up;** the initial implementation may ship without it, in which case the only way to re-enable the dialog is to reinstall the app or manually wipe app data.

## Architecture & Implementation Notes

- **`GroupTargetSheet` is a `StatelessWidget`** that consumes `AppState` via `context.watch<AppState>()`. All callbacks (`onAdd`, `onRemove`, `onMove`) come in as constructor params from the screen — the sheet never mutates state directly.
- **`PreferencesRepository`** gains `setSkipMoveConfirmation(bool)` / `getSkipMoveConfirmation() -> bool`. `AppState.load()` reads it during init and stores in `_skipMoveConfirmation` with a public getter.
- **Empty-section hiding** is implemented per-section in `GroupTargetSheet.build()` — each section computes its row list, returns `SizedBox.shrink()` if empty.
- **Atomic move:** `_moveBetweenGroups` performs both list mutations inside one `setState` block; the rendering layer never sees the target out of both groups.
- **No animation work in v1.** The sheet uses Material's default slide animation; sections appear/disappear without transitions when emptied.

## Edge Cases

- **Target goes offline while the sheet is open:** the sheet rebuilds on `AppState` notifications. The offline target disappears from `AVAILABLE` / `ASSIGNED ELSEWHERE` and remains in `IN THIS GROUP` as a greyed-out row (existing online/offline styling carries through `TargetNameResolver`).
- **Group is deselected while sheet is open:** not currently reachable — there's no "deselect group" gesture. If a future change adds one, the sheet should close.
- **Drill starts (LIVE) while sheet is open:** the start-drill button is in the screen's `TacticalAppBar`, not behind the sheet, so tapping it is possible. The sheet should dismiss automatically when `state.phase` transitions out of `idle`. Implement via a phase-watcher inside the sheet that calls `Navigator.pop` on transition.
- **All targets offline:** sheet shows empty state line (see §2).
- **Undo of a move when the target has since gone offline:** undo still mutates `groups` (which only stores ids); the target reappears in its prior group as offline. Acceptable.
- **User taps the same group card twice in a row:** the second tap is a no-op because `showModalBottomSheet` is already presenting; the second tap will be absorbed by the scrim. Confirmed behavior, no additional handling needed.

## Testing

- **Widget tests for `GroupTargetSheet`**: section visibility (empty sections hidden), tap dispatches (`onAdd`, `onRemove`, `onMove` callbacks fire with correct ids), confirmation dialog shown for ASSIGNED ELSEWHERE taps when `skipMoveConfirmation == false`, dialog skipped when flag is true.
- **Widget tests for the dialog**: cancel discards, move dispatches, "Don't show again" persistence boundary (calls a fake `PreferencesRepository`).
- **Widget tests for the screen** (`program_a_setup_screen_test.dart`): tapping a group card opens the sheet. (Pre-existing `DrillTemplateRepository` test infrastructure issue must be resolved as part of this work — see Migration §1.)
- **Manual smoke test on iPhone:** the scenario that originally failed (assign 4 targets to one group, confirm no overflow) is validated by the absence of in-place expansion; verify cross-group move flow + confirmation suppression + undo SnackBar behaviors on-device.

## Migration / Cleanup

1. **Repair `test/screens/program_a_setup_screen_test.dart`** — currently fails with `ProviderNotFoundException` for `DrillTemplateRepository`. Add a `MultiProvider` wrapper supplying a fake `DrillTemplateRepository` (a fake helper already exists at `test/test_helpers/fake_drill_template_repository.dart`). This unblocks adding the new screen-level test that asserts "tap card opens sheet."
2. **Delete `_CollapsedLabels`'s sibling expanded-Wrap path** in `lib/widgets/tactical/group_node_card.dart`. Keep `_CollapsedLabels`; remove the `expanded ? ... : _CollapsedLabels(...)` conditional and inline `_CollapsedLabels(...)` as the only render path.
3. **Remove `expanded` from `GroupNodeCard` constructor** and update the consolidated tests in `test/widgets/tactical/group_node_card_test.dart` to drop the `expanded:` param everywhere.
4. **Remove the collapse-on-empty defensive fix** (`_expandedGroupIndex = null` block in `_removeTargetFromGroup`) — `_expandedGroupIndex` no longer exists.

## Out of Scope (Possible Follow-ups)

- Animating section transitions when targets migrate between sections.
- Drag-to-reorder within `IN THIS GROUP`.
- Multi-select in `AVAILABLE` ("add all").
- Per-group color in the sheet header (currently the title uses default text color regardless of group).
- A "Reset move confirmations" UI surface if the §8 polish ships as a separate task.
- Persisting `selectedGroupIndex` across app restarts.
