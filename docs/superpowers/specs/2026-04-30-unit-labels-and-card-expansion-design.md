# Unit Labels & Card Expansion — Design Spec

**Date:** 2026-04-30
**Status:** Approved (brainstorming)
**Scope:** UI-only changes to drill results dossier and target allocation grid

## Problem

Three friction points in the current UI:

1. The default unit label `NODE_##` is misleading — these are reactive target units, not generic nodes. Users have asked for a label that reflects the product domain.
2. The post-drill `EVENT_LOG` is a flat chronological feed. Users investigating a single unit's performance must mentally filter the global log to find that unit's events.
3. Group cards in the allocation grid render a `T# ✕` chip per assigned target, causing horizontal overflow when a group has 2+ units. Cards lose their uniform size, breaking grid alignment.

## Goals

- Rename the default unit label to a domain-correct, tactically-styled token without breaking custom user-assigned names.
- Let users see per-unit event detail without leaving the results screen and without losing the global chronological view.
- Keep group cards a fixed size regardless of how many units are assigned, while still letting users remove specific targets from a group.

## Non-Goals

- Renaming database identifiers, BLE addresses, or any persistent ID fields.
- Restructuring the underlying event/session schema.
- Changing the allocation flow itself (drag-to-assign, group creation/deletion).
- Adding multi-card expansion or any new bulk-edit affordance.

## Design

### 1. Target-Unit Label Rename → `T/U_##`

**What is a "target unit":** A single physical reactive target. In the current UI it appears as `T1`, `T2`, `T4`, `T6` (chips inside a group card) and as `NODE_T1`, `NODE_T2`, ... `NODE_T6` (rows in the post-drill `PER_NODE` section).

**Out of scope of the rename:** Group / controller-node labels (e.g. the `NODE_01 GROUP 01` header on a group card) are a separate concept and are NOT changed by this work.

**Format:** `T/U_` + zero-padded two-digit display index (e.g. `T/U_01`, `T/U_02`, ... `T/U_12`).

**Scope of change:** Display-only. The `T/U_##` string is derived from a target unit's display index at render time. No database migration, no identifier changes.

**Surfaces affected:**
- Group card unit chips: `T1 ✕ T2 ✕` → `T/U_01 ✕ T/U_02 ✕` (rendering rules for the chips themselves are governed by §3 — collapsed view shows units only without `✕`).
- Post-drill `PER_NODE` summary rows: `NODE_T1 HITS 4 ...` → `T/U_01 HITS 4 ...`.
- Post-drill `EVENT_LOG` entries that reference a target unit by name: `Target 1 activated` → `T/U_01 activated`; `Late hit on Target 1` → `Late hit on T/U_01`; `Target 1 hit 1/3` → `T/U_01 hit 1/3`; `Target 1 complete (14219ms)` → `T/U_01 complete (14219ms)`.
- Any other in-app surface that currently renders the target-unit default label in `T#` or `NODE_T#` form.

**Custom names:** If a target unit has a user-assigned custom name, the custom name continues to render. `T/U_##` is the default only.

### 2. Expandable `PER_NODE` Rows in Results

Each row in the `PER_NODE` section of the results dossier becomes a tap target.

**Collapsed state (default):** Identical to today's row — `T/U_01  HITS 5  DONE 2  AVG 11469MS  NS 0  LATE 0` — with a `▸` chevron added at the right edge.

**Expanded state:** Row reveals an inline, indented list of that unit's chronological events. Format matches the global event log row format (e.g. `T/U_01 activated  16:17:32`, `T/U_01 hit 1/3  16:17:46`, `Late hit on T/U_01  16:17:47`). Chevron rotates to `▾`.

**Interaction:**
- Single-expand: at most one `PER_NODE` row is expanded at a time. Tapping a second row collapses the previously expanded one.
- Tapping an expanded row's header collapses it.
- Expansion does not affect the global `EVENT_LOG` section below — that remains a complete chronological feed.
- The `EVENT_LOG` section's content and behavior are unchanged.

**Data:** The expanded view is a filter over the same event timeline already used to render `EVENT_LOG`. No new data, no new query.

### 3. Group Card Fixed-Size + Tap-to-Expand

**Collapsed state (default):**
- Card shows the existing group header unchanged (e.g. `NODE_02 ✓ GROUP 02`) and a horizontal list of target-unit labels using the new format (`T/U_04  T/U_06`).
- No `✕` remove buttons in collapsed state.
- Card height is fixed regardless of how many target units are assigned.
- If unit labels would overflow horizontally: wrap to a max of 2 lines, then truncate the remaining with `…` (full list visible on expand).

**Expanded state:**
- Tapping the card expands it in place. The card grows downward; other cards in the allocation grid reflow below it.
- Expanded card shows each assigned target unit as its own chip with a `✕` remove button: `T/U_04 ✕   T/U_06 ✕`.
- Remove buttons remove that target unit from the group, behaving identically to today's per-chip remove behavior.
- A close affordance (tap card header again, or tap outside the card) collapses it.

**Interaction:**
- Single-expand: at most one group card in the allocation grid is expanded at a time. Tapping a second card collapses the previously expanded one.
- Standby cards (`STANDBY` state, no group assigned) do not have an expanded state — they remain non-interactive placeholders as today.
- Group selection state (the magenta/cyan border indicating selected group) is independent of expansion state.

## Architecture & Implementation Notes

- **Label derivation:** Centralize the default-label logic in a single helper (e.g. `Unit.displayLabel`) that returns the custom name if set, else `T/U_${index.toString().padLeft(2, '0')}`. All call sites (allocation grid, group cards, results) consume this helper. Search-and-replace existing `NODE_${...}` formatters to use the helper.
- **PER_NODE expansion state:** Local to the results screen widget. A single `int? expandedUnitIndex` field tracks which row is expanded. No persistence — each visit to results starts fully collapsed.
- **Group card expansion state:** Local to the allocation grid widget. A single `int? expandedGroupIndex` field tracks which card is expanded. No persistence.
- **Reflow:** Use the existing grid layout and let it naturally reflow when one cell's height changes. No animation required for v1; if expansion feels janky, add a 150ms ease-out height tween in a follow-up.

## Edge Cases

- **Group with zero units assigned but in non-standby state:** Should not be reachable through normal allocation flow; if it occurs, render an empty unit list and disable expansion.
- **Group with 6+ units:** Truncation with `…` covers this in collapsed view; expanded view scrolls vertically within the grid cell if needed.
- **Custom unit name longer than the card width:** Truncate with `…` in the collapsed group card; show full name in expanded view.
- **Drill in progress:** These changes apply to the post-drill results screen and the pre-drill allocation grid. No live-drill UI is affected (consistent with "no live drill telemetry" rule).

## Testing

- **Widget tests** for the label helper: verifies `T/U_01` formatting, custom-name override, zero-padding boundaries.
- **Widget tests** for `PER_NODE` row expansion: tapping expands, tapping a second row collapses the first, tapping an expanded row collapses it.
- **Widget tests** for group card expansion: tapping expands, second tap collapses, only one card expanded at a time, remove-target action still works in expanded state.
- **Visual smoke check** on a results screen with 5+ units to confirm no overflow and chevron rotation renders cleanly.

## Out of Scope (Possible Follow-ups)

- Animating expansion transitions.
- Allowing multiple simultaneous `PER_NODE` expansions (rejected during brainstorming — single-expand chosen for cleanliness).
- Allowing rename-from-results (custom unit naming is assumed to live in setup; not changed here).
- Reorganizing the global `EVENT_LOG` (e.g. filter chips). The `PER_NODE` expansion is the per-unit view; the log stays chronological.
