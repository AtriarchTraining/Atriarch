# Target Setup Screen Pass — Design

Date: 2026-05-11
Status: Approved (pending spec review)

## Goal

Make the Target Setup screen actually useful: replace the stub Walk-the-Range
button, surface a per-target list with flash (identify) buttons, and introduce
persistent target groups so instructors don't re-build groupings every drill.

App-only scope. No firmware, hardware, or protocol changes. Battery indicator
is explicitly deferred to a separate spec.

## Background

Today the target setup screen
([lib/screens/target_setup_screen.dart](../../../lib/screens/target_setup_screen.dart))
shows a single "X of Y online" card plus a `WALK_THE_RANGE` button that is a
TODO stub (only re-runs discovery and shows a SnackBar). The real
walk-the-range routine already exists on the home screen
([lib/screens/home_screen.dart:122-131](../../../lib/screens/home_screen.dart)),
where it iterates online targets, TTS-speaks each name, and sends the existing
`IDENT/<id>/` command which is wired to `CMD_IDENTIFY` in firmware
([firmware/transmitter_esp32/config.h:39](../../../firmware/transmitter_esp32/config.h)).

`TargetUnit.groupId` is declared in the model but is never read or written
anywhere in the codebase — dead field. Groups today are only formed per-drill
inside Program A/B setup screens.

## Non-goals

- Battery telemetry. Current hardware has no VBAT pin, voltage divider, or
  protocol field. Separate spec will cover the hardware + firmware + protocol
  + UI work.
- Photo-map (already a disabled placeholder; stays disabled).
- Drag-to-reorder targets.
- Renaming targets from this screen (handled elsewhere).
- Any change to the drill-time grouping UX inside Program A/B setup —
  persistent groups only **seed** the initial drill config; per-drill editing
  is unchanged.

## Design

### 1. Walk-the-Range deduplication

Extract the walk loop into `AppState.walkTheRange()`. Both the home screen
button and the target setup screen call it. Behavior preserved exactly:
iterate `targets.where(isOnline)`, TTS-speak resolved display name, send
identify, 2-second delay.

The stub on `target_setup_screen.dart:35` is deleted.

### 2. Target Setup screen layout

```
TARGET SETUP
┌───────────────────────────────────────────┐
│ 4 of 5 targets online                     │
└───────────────────────────────────────────┘

GROUPS
[G1: Left bank ✎] [G2 ✎] [G3: No-shoots ✎] [+ Add group]

TARGETS
┌───────────────────────────────────────────┐
│ ● Target 1     "Alpha"                    │
│   [G1: Left bank ▾]          [⚡ Flash]   │
├───────────────────────────────────────────┤
│ ● Target 2                                │
│   [None ▾]                   [⚡ Flash]   │
├───────────────────────────────────────────┤
│ ○ Target 3     offline                    │
│   [G2 ▾]                     [⚡ Flash]   │
└───────────────────────────────────────────┘

[ WALK_THE_RANGE ]
[ PHOTO_MAP (disabled) ]
[ RESCAN ]
```

**Header card:** compressed version of the existing online-count card.

**Groups chip row:** horizontally scrollable list of all known persistent
groups in `target_group_order`. Each chip shows `G<n>` plus optional label
(`G1: Left bank`). Tap chip → dialog with Rename / Delete actions. Delete
unassigns all targets from that group but leaves them online. The `+ Add
group` chip creates the next sequential group number and opens the rename
dialog immediately.

**Target list:** scrollable. One row per known target (online + offline known
from prior sessions). Row contents: status dot, "Target N", optional display
name, group picker chip, flash button.

**Group picker** (per row): popup menu with `None`, every existing group,
and `+ New group…` at the bottom. Picking "New group" creates the next
sequential group number, assigns this target, and opens the rename dialog.

**Flash button:** calls `AppState.identifyTarget(id)` — offline targets show
the button disabled.

**Bottom buttons:** unchanged (`WALK_THE_RANGE`, disabled `PHOTO_MAP`,
`RESCAN`).

### 3. Persistent group storage

New `PreferencesRepository` keys, sibling to the existing `target_names`:

- `target_groups` — `Map<int targetId, int groupNumber>`. Unassigned targets
  have no entry.
- `target_group_labels` — `Map<int groupNumber, String label>`. Optional
  custom labels; missing entry means the chip just displays `G<n>`.
- `target_group_order` — `List<int>` of group numbers in display order. The
  source of truth for "which groups exist" (a group exists if it's in this
  list, regardless of whether anything is assigned to it).

Group numbers are arbitrary stable integers. Deleting `G2` does **not**
renumber `G3 → G2`; the next created group is `max(existing) + 1`. No hard
cap on count.

### 4. AppState API

```dart
// Reads
Map<int,int>     get targetGroupAssignments;  // targetId -> groupNumber
Map<int,String>  get targetGroupLabels;       // groupNumber -> label
List<int>        get targetGroupOrder;        // ordered group numbers

// Writes
Future<void> setTargetGroup(int targetId, int? groupNumber);
Future<int>  createTargetGroup({String? label}); // returns new group number
Future<void> renameTargetGroup(int groupNumber, String? label);
Future<void> deleteTargetGroup(int groupNumber); // unassigns members

// Walk-the-range
Future<void> walkTheRange();

// Drill seeding
List<TargetGroup> buildSeededGroups();
```

`buildSeededGroups()` walks `targetGroupOrder`, emits one `TargetGroup` per
group that has at least one assigned target. Empty persistent groups are
**not** emitted into drill config (they're a setup convenience, not a drill
artifact).

### 5. Drill seeding behavior

`ProgramASetupScreen` and `ProgramBSetupScreen` currently build initial
`DrillConfig.groups` from scratch. Change:

- If launching a drill from scratch (no template): initial groups come from
  `state.buildSeededGroups()` instead of being empty.
- If launching from a saved drill template: template groups win (existing
  behavior, unchanged).
- Drill-time group edits **do not** write back to persistent storage. The
  setup screen's persistent groups are the seed only.

This is the minimum change to honor the user's accepted approach ("persistent
groups seed drill groups") without touching the locked grouping/config UX.

### 6. Model cleanup

Remove the dead `TargetUnit.groupId` field. Assignment lives in `AppState` +
preferences, keyed by target id. This survives target offline/online cycles
and keeps the BLE runtime object focused on transport state.

### 7. New files / touched files

**New:**
- `lib/widgets/target_setup/target_row.dart` — single target row widget.
- `lib/widgets/target_setup/group_chip_row.dart` — horizontal chip list with
  add/rename/delete behavior.
- `lib/widgets/target_setup/group_picker.dart` — per-row group selection
  popup including "+ New group".

**Modified:**
- `lib/screens/target_setup_screen.dart` — rewrite body using new widgets.
- `lib/screens/home_screen.dart` — replace local walk loop with
  `state.walkTheRange()`.
- `lib/state/app_state.dart` — add `walkTheRange`, group APIs, hold
  in-memory caches loaded from prefs.
- `lib/services/preferences_repository.dart` — add reads/writes for the
  three new keys.
- `lib/models/target_unit.dart` — drop the unused `groupId` field.
- `lib/screens/program_a_setup_screen.dart`,
  `lib/screens/program_b_setup_screen.dart` — initial-groups path calls
  `buildSeededGroups()` when not loading a template.

### 8. Testing

**Unit:**
- `PreferencesRepository` — round-trip `target_groups`, `target_group_labels`,
  `target_group_order`. Handles missing keys, malformed entries.
- `AppState.createTargetGroup` — returns `max(existing) + 1`, appends to
  order list, persists.
- `AppState.deleteTargetGroup` — unassigns members, removes from order +
  labels.
- `AppState.buildSeededGroups` — empty state, partial assignments, multiple
  groups, groups with no members (must be omitted).

**Widget (fake repos per the established widget-test policy — no FFI
sqflite):**
- Target row renders status, name, group chip, flash button; tapping flash
  fires `identifyTarget`.
- Group chip row: `+ Add group` opens rename dialog; rename persists; delete
  removes chip and clears member assignments.
- Group picker: shows None + existing + New group; "New group" creates +
  assigns + opens rename dialog.
- Program A setup with persistent assignments produces seeded groups; with
  no assignments produces empty groups.

## Risks and mitigations

- **Group numbers drift over time** (delete G2, create G3, delete G3 →
  next is G4 with G1 as the only remaining group). Acceptable; label
  display makes the actual number invisible to most users. The chip row
  shows order, not numbering, so visual continuity is preserved.
- **Persistent groups conflict with template groups.** Templates win on
  load (unchanged). Persistent groups only seed scratch drills.
- **Empty persistent groups.** Allowed in setup (instructor can pre-create
  group labels before targets discover). Not emitted into drill config.

## Out of scope (future specs)

- Battery telemetry — hardware mod (voltage divider to ADC), firmware
  read + telemetry frame, protocol extension, UI display.
- Photo-map.
- Drag-to-reorder groups or targets.
- Sync persistent groups to the cloud / Range Buddy.
