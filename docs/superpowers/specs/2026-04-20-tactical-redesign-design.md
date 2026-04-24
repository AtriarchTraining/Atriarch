---
spec: Tactical Redesign (App-Wide)
date: 2026-04-20
status: approved
---

# Tactical Redesign — App-Wide

Redesign every screen in the Flutter app to the tactical dark aesthetic
referenced in the user's HTML mockup (tight-tracked uppercase labels,
sharp rectangles, `PARAM_01` numeric section headers, neon-green `LIVE`
status indicator, large tabular numerics, subtle grid background).

## Scope

In: theme, typography, top app bar, all six screens, shared widgets.

Out: bottom navigation (user opted to keep push-flow), light theme
(retired for this pass), any functional behavior change, protocol /
firmware / state logic.

## Non-negotiables preserved

- **Press-and-hold STOP** on drill-running — 800ms ring fill, reduce-motion
  fallback, `Semantics(button, enabled, label)`. Restyle the button shape
  and ring; do **not** change the gesture or timing.
- **Arming-failed banner retry** behavior on Program A/B.
- **`PopScope(canPop: false)`** on drill-running.
- All existing `Semantics` labels remain.

## Foundations

### Theme default

`MaterialApp.themeMode` → `ThemeMode.dark`. `buildAtriarchDarkTheme()` becomes
the primary theme builder. `buildAtriarchLightTheme()` stays in the file but is
no longer referenced from `main.dart`. Existing `AtriarchTokens.dark` palette
is reused as-is — already matches the reference.

### Typography

Swap Inter Tight → **Space Grotesk** across `bodyX`, `headlineX`, `titleX`,
`labelX`. Keep **JetBrains Mono** for `displayX` (used for tabular numerics:
timer, stats). Headlines: `letterSpacing: -0.5`, `FontWeight.w700`. Labels:
`letterSpacing: 2.4` (equivalent to `0.2em` at 12pt), uppercase via
`TextStyle` or `.toUpperCase()` at call sites.

Add a `labelTiny` style (10pt, bold, wide-tracked, `textTertiary`) for the
`PARAM_01` / `NODE_01` / `PROTOCOL_STATUS` micro-labels.

### Radius

`AtriarchRadius.sm`, `md`, `lg` all → `0`. Keep `full: 9999` for status dots
and the press-and-hold ring. Card/Input/Button `shape:` in `ThemeData` uses
zero radius.

### Tactical grid background

New `TacticalGridBackground` widget. `CustomPaint` that draws a 20px grid of
`AtriarchTokens.border` at ~10% alpha (`Color.fromRGBO(42, 49, 64, 0.1)`).
Wraps the body of every Scaffold via a `builder` in `MaterialApp` OR applied
per-screen inside a shared `TacticalScaffold` wrapper (see below).

### Top app bar

Custom `TacticalAppBar` (`PreferredSizeWidget`), 64px tall. Replaces Material
`AppBar` everywhere. Layout:

```
[ menu ]  TITLE_UPPERCASE          [ statusChip ]
         ─────────────────────────── (hairline bottom border)
```

Left: hamburger icon (`Icons.menu`) + title in wide-tracked uppercase
(`letterSpacing: 3.2`, `FontWeight.w900`, `statusHit` blue).

Right: `TacticalStatusChip` reflecting transmitter connection (the `BleService`
connection state already lives in `AppState`). Chip shows a 2px colored dot
(`statusLive` / `statusOffline`) with 8px glow + a label: `LIVE` / `OFFLINE`.

Bottom: 1px `border` color hairline. No shadow, no Material elevation.

### Shared scaffold wrapper

`TacticalScaffold` wraps `Scaffold`, always applies:
- `TacticalGridBackground` behind `body`
- `TacticalAppBar` if `title` is provided
- Dark background (`tokens.bgBase`)

Every screen migrates from `Scaffold(...)` to `TacticalScaffold(...)`.

## Reusable widgets

All new widgets live in `lib/widgets/tactical/`.

### `TacticalSection`

Section header pattern:
```
[PARAM_01]  ────────────  [OPTIONAL_TRAILING_LABEL]
```
Props: `code` (e.g. `"PARAM_01"`), `trailing` (optional string). Code chip is
`labelTiny` inside a 1px `outline` border, `bgCard` fill, 2px horizontal / 1px
vertical padding. Divider is `outline-variant` at 30% alpha.

### `TacticalCard`

Container with:
- `tokens.bgCard` fill
- Zero radius
- Optional 2px left border (`accent` prop, defaults to transparent)
- Slot for `header` row + `child`

Replaces ad-hoc `Container`/`Card` usage in setup screens.

### `TacticalStepper`

Replaces `IncDec`.

Layout:
```
[ − ]   4 2 . 5      [ + ]
        SECONDS
```

- `−` / `+`: 48×48 square buttons, `surface-container-highest` fill, 1px
  `outline-variant` border at 50%, active state flashes the primary color at
  20% alpha.
- Number: `displaySmall` (JetBrains Mono, 36pt, `FontWeight.w700`, tabular
  numerics, `letterSpacing: -1`).
- Unit: `labelTiny` centered under the number.

Props: `controller: TextEditingController`, `label: String`, `step: double`
(default 1), `unit: String` (e.g. `"SEC"`, `"MS"`, `"HITS"`, `"COUNT"`),
`min: double?`, `max: double?`, `compact: bool` (default false).

**Compact variant** (`compact: true`): 36×36 buttons, 20pt number, used
inside `TacticalMinMaxCard`.

### `TacticalMinMaxCard`

Convenience widget. One `TacticalCard` containing:
- Header row: `label` (e.g. `"START DELAY"`) left, range hint right
  (e.g. `"0.25 – 10.00 SEC"`)
- Two compact `TacticalStepper`s side-by-side, separated by a 1px vertical
  divider. Left one shows `MIN` micro-label under the number; right shows
  `MAX`.

Used 3× on Program A and Program B (Start Delay, Time Between Activations,
Required Hits).

### `TacticalPrimaryButton`

The commit / start action.

Full-width, 56px tall, `tokens.statusHit` fill (the blue primary),
`tokens.bgBase` foreground, zero radius, wide-tracked uppercase label, lightning
(`Icons.bolt`) or custom leading icon.

Variants via `variant:` enum:
- `primary` (blue): "COMMIT // START DRILL", etc.
- `loading`: blue fill + spinner + `ARMING…` label, disabled
- `destructive`: `statusViolation` fill, for the abort/stop affordance
- `disabled`: `statusOffline` fill at 40% alpha

Active-state: 0.98 scale on press (`GestureDetector` + `AnimatedScale`).

### `TacticalStatusChip`

Small indicator. Layout: `[2px dot with glow]  LABEL`. Props: `color`,
`label`, `glow: bool` (default true).

Used: top-bar transmitter state, inline drill phase indicator on setup
screens (`LIVE` badge next to program title), drill-running header.

### `GroupNodeCard`

Replaces the Program A group `Card`.

2-col grid cell. Two visual states:

**Assigned** (group has targets):
- `bgCard` fill
- 2px left border in that group's color (`tokens.groupColor(groupIndex)`)
- Top-right: 14px filled `Icons.check_circle` in the group color
- Header block: `NODE_0N` micro-label + `GROUP 0N` title (`FontWeight.w700`,
  slight negative tracking)
- Footer row: `ASSIGNED` label + 24×4 filled bar in the group color
- Below footer: wrap of target chip deletables (existing `targetIds` list)

**Standby** (no targets):
- `bgCard` fill at 50% alpha
- 1px outline-variant border (no accent)
- Dimmed header/footer labels
- No check icon, indicator bar at 30% alpha

**Selected** (tapped to assign into): overlay 2px outline in `statusHit` blue
around the whole cell, regardless of assigned/standby state.

Tap behavior unchanged — selects this group as the assign target, then
tapping an online target chip elsewhere adds to its `targetIds`.

### `TargetNodeChip`

Replaces `TargetChip`.

36×36 square, outlined 1px in `outline-variant`, `bgCard` fill, shows:
- `T##` number centered (`labelLarge`, JetBrains Mono, tabular)
- Top-right 6px status dot: `statusLive` online / `statusViolation`
  no-shoot / `statusOffline` offline
- Tap handler unchanged

### `TacticalHudTile`

For drill-running and results KPI rows.

Small card: `labelTiny` top label, big mono numeric below, optional unit
suffix. Example: `HITS // 12`, `ELAPSED // 14.7S`.

## Per-screen layouts

### `home_screen.dart`

`TacticalScaffold(title: "ATRIARCH // HOME", ...)`. Body:

```
[ ConnectionBanner — full-width tactical bar ]
  ● CONNECTED · DeviceName              (tokens.statusLive bg at ~15% alpha,
                                         solid accent border-bottom)
  OR
  ● DISCONNECTED — TAP TO RECONNECT     (statusViolation)
  
  Tapping when disconnected pushes DeviceDiscoveryScreen
  (same behavior as current _ConnectionBanner).

PROTOCOL_SELECT ───────────────────────

[ TacticalCard: border-left outline-variant ]
  TARGET_SETUP
  Scan the fleet, identify units, mark no-shoots.           →
  (Currently shows placeholder snackbar — preserve behavior.)

[ TacticalCard: border-left statusHit ]
  PROGRAM_A
  GROUP MODE
  Up to 5 groups. One active target per group.              →

[ TacticalCard: border-left statusHit ]
  PROGRAM_B
  INDIVIDUAL MODE
  Every target runs its own reaction drill.                 →
```

The ConnectionBanner is **not** the top app bar status chip — that chip
shows drill/transmitter state globally, but the home screen retains its own
richer banner for the reconnect affordance. Both can coexist.

Routes and handlers preserved verbatim from current `home_screen.dart`.

### `device_discovery_screen.dart`

**Purpose correction:** This screen pairs with the **BLE transmitter**
(via `flutter_blue_plus`), not with targets. It's shown at app startup
when no transmitter is connected and from the home connection banner's
reconnect affordance.

`TacticalScaffold(title: "TRANSMITTER // PAIRING", ...)`. Body:

- Header: `PROTOCOL_STATUS` → `TRANSMITTER / PAIRING`, top-right chip shows
  `SCANNING` (armed amber) or `IDLE` (offline grey).
- `TacticalSection(code: "PARAM_01", trailing: "SCAN_CONTROL")` — full-width
  `TacticalPrimaryButton`. `SCAN` (primary) / `SCANNING…` (loading variant
  with spinner) / `STOP SCAN` (destructive) based on `FlutterBluePlus.isScanning`.
- `TacticalSection(code: "PARAM_02", trailing: "DEVICES_DETECTED")` — list
  of `TacticalCard`s, one per `ScanResult`:
  - Left: tiny connection-type icon (bluetooth)
  - Title: `device.platformName` or remoteId (`labelLarge`)
  - Subtitle: remoteId in mono (`labelTiny`, textSecondary)
  - Right: `${rssi} dBm` in mono, colored by strength
  - Tap (if connectable): calls `_connectAndNavigate` (existing handler)
  - Empty state: muted `SCANNING FOR DEVICES…` text

FAB removed — the PARAM_01 primary button supersedes it.
Pull-to-refresh preserved via `RefreshIndicator`.

### `program_a_setup_screen.dart`

`TacticalScaffold(title: "PROGRAM_CONFIG", ...)`. Body:

- Header block:
  ```
  PROTOCOL_STATUS
  PROGRAM A / GROUP MODE          ● LIVE
  ```
  (`LIVE` chip only when transmitter connected.)
- `TacticalSection(code: "PARAM_01", trailing: "TIMING")`
  - `TacticalMinMaxCard` "START DELAY" (sec, step 0.25, 0.00–10.00)
  - `TacticalMinMaxCard` "TIME BETWEEN ACTIVATIONS" (sec, step 0.25)
  - `TacticalMinMaxCard` "REQUIRED HITS" (count, step 1, integer)
- `TacticalSection(code: "PARAM_02", trailing: "ITERATIONS")`
  - Single `TacticalStepper` card, label `ITERATIONS PER GROUP`, unit `COUNT`.
- `TacticalSection(code: "PARAM_03", trailing: "ALLOCATION_GRID")`
  - 2-col grid of 5 `GroupNodeCard`s. Tap selects. Empty 6th cell left blank
    or filled with a tiny `+ CUSTOM` hint disabled for Gate 1.
- `TacticalSection(code: "PARAM_04", trailing: "AVAILABLE_NODES")`
  - Wrap of `TargetNodeChip`s for unassigned online targets. Empty state:
    muted `ALL NODES ASSIGNED` text.
- Arming-failed banner (existing behavior, restyled): `TacticalCard` with 2px
  left border in `statusViolation`, warning icon in red,
  `NO RESPONSE FROM TRANSMITTER // CHECK CONNECTION`, outline `RETRY` button
  on the right.
- `TacticalPrimaryButton` "COMMIT // START DRILL" (primary variant) /
  "ARMING…" (loading).

### `program_b_setup_screen.dart`

Same as Program A minus the group allocation sections.

Also: the existing `_ScanFab` FloatingActionButton is **replaced** by inline
button. Add `TacticalSection(code: "PARAM_00", trailing: "NODE_SCAN")` at top
with a secondary-styled `TacticalPrimaryButton` ("SCAN FOR NODES"). Keeps
visual language consistent and removes the floating button's roundness from
an otherwise zero-radius screen.

Sections:
- `PARAM_00 // NODE_SCAN` — scan button
- `PARAM_01 // TIMING` — Start Delay, Time Between Activations, Required Hits
  (3× `TacticalMinMaxCard`)
- `PARAM_02 // ITERATIONS` — single `TacticalStepper` card
  (label: `ITERATIONS PER TARGET`)
- `PARAM_03 // NODES` — target count summary (`N TARGET(S) ONLINE // M
  NO-SHOOT`) in `labelTiny`
- Arming-failed banner (same as Program A)
- `TacticalPrimaryButton` (primary / loading)

### `drill_running_screen.dart` — HUD layout

`TacticalScaffold(title: "DRILL // LIVE", ...)`. Top-bar chip shows a pulsing
`statusLive` dot when running, `statusArmed` when stopping.

Body, vertically centered column:

1. Small breathing `DRILL ACTIVE` label in `statusArmed` (existing behavior:
   reduce-motion still swaps breathing animation off).
2. Four **corner brackets** (8×8 L-shaped marks in `statusHit` blue) framing
   the timer block — CustomPaint, static.
3. **Hero timer**: `DrillTimer` upgraded to JetBrains Mono at 80pt,
   `FontWeight.w700`, `letterSpacing: -2`, tabular numerics. Format
   `MM:SS.ss`.
4. Row of three `TacticalHudTile`s:
   - `HITS // 12`
   - `ELAPSED // 14.72S`
   - `CURRENT NODE // T03` (or `GROUP ALPHA` on Program A)
5. If Program A: a strip of 5 mini group-state cells (16×8 bars) below the
   HUD tiles. Active group filled in its group color, others dim.
6. Large spacing, then the press-and-hold **STOP** button, restyled:
   - Square 200×200 button inside a 220×220 frame, `statusViolation` fill,
     zero radius
   - `_StopRingPainter` kept unchanged — still draws a circle of radius
     `(size.width / 2) - 6` around the square. Circle-ring-around-square is
     the intentional tactical detail.
   - White `STOP` label, JetBrains Mono 42pt, letter-spacing 3
   - `STOPPING…` state: spinner + label unchanged, just reskin typography
7. Below STOP: `PRESS AND HOLD TO ABORT` helper label in `textTertiary`.

All existing behavior (`PopScope`, press-and-hold gesture, 800ms timing,
2s stopping fallback, `forceDrillFinished` call) preserved unchanged.

### `results_screen.dart` — run dossier

`TacticalScaffold(title: "RESULTS // DOSSIER", ...)`. Body:

- Header: `PROTOCOL_STATUS` → `DRILL COMPLETE` + timestamp in mono.
- `TacticalSection(code: "SUMMARY_01", trailing: "KPI")` — 2-col grid of six
  `TacticalHudTile`s:
  - `DURATION // 1m 34s`
  - `ACTIVATIONS // N`
  - `TOTAL HITS // N`
  - `COMPLETIONS // N` (green accent)
  - `NO-SHOOT // N` (red accent if > 0)
  - `LATE HITS // N` (amber accent if > 0)
- `TacticalSection(code: "SUMMARY_02", trailing: "PER_NODE")` — replace
  Material `DataTable` with a list of `TacticalCard`s, one per target:
  ```
  NODE_T03       HITS // 4   DONE // 3   AVG // 842MS   NS // 0   LATE // 1
  ```
  Headers as `labelTiny`, values in mono. Horizontal scroll kept if needed.
- `TacticalSection(code: "SUMMARY_03", trailing: "EVENT_LOG")` — list view of
  events, restyled rows:
  - Left: 2px status-color bar (green / blue / red / amber / tertiary)
  - Middle: event text + target id
  - Right: `HH:MM:SS` in mono
  Replaces `ListTile` but same content as `_EventTile` produces.
- Floating home button → replaced by a full-width `TacticalPrimaryButton`
  `NEW DRILL` at the end of the scroll column (not pinned/sticky). FAB
  removed — inconsistent with the zero-radius aesthetic.

## File-level changes

New:
- `lib/widgets/tactical/tactical_app_bar.dart`
- `lib/widgets/tactical/tactical_scaffold.dart`
- `lib/widgets/tactical/tactical_grid_background.dart`
- `lib/widgets/tactical/tactical_section.dart`
- `lib/widgets/tactical/tactical_card.dart`
- `lib/widgets/tactical/tactical_stepper.dart`
- `lib/widgets/tactical/tactical_min_max_card.dart`
- `lib/widgets/tactical/tactical_primary_button.dart`
- `lib/widgets/tactical/tactical_status_chip.dart`
- `lib/widgets/tactical/tactical_hud_tile.dart`
- `lib/widgets/tactical/group_node_card.dart`
- `lib/widgets/tactical/target_node_chip.dart`

Modified:
- `lib/theme/atriarch_theme.dart` — Space Grotesk font, zero radius, add
  `buildAtriarchDarkTheme()` or equivalent, new `labelTiny` text style.
- `lib/main.dart` — `themeMode: ThemeMode.dark`, wire dark theme builder.
- `lib/widgets/inc_dec.dart` — deleted (replaced by `TacticalStepper`).
- `lib/widgets/target_chip.dart` — deleted (replaced by `TargetNodeChip`).
- `lib/widgets/drill_timer.dart` — restyled with new typography.
- `lib/screens/home_screen.dart` — new layout.
- `lib/screens/device_discovery_screen.dart` — new layout.
- `lib/screens/program_a_setup_screen.dart` — new layout.
- `lib/screens/program_b_setup_screen.dart` — new layout, FAB removed.
- `lib/screens/drill_running_screen.dart` — new layout, gesture preserved.
- `lib/screens/results_screen.dart` — new layout, FAB removed, DataTable
  replaced.

## Fonts

`google_fonts` is already a dependency. Use `GoogleFonts.spaceGrotesk(...)`
in `atriarch_theme.dart` the same way Inter Tight is referenced today.
First-run network fetch is acceptable for this app — Space Grotesk is not
bundled as a local asset unless bundle-size review later decides otherwise.

## Testing

- Existing widget tests in `test/` should pass with minimal updates — most
  reference button labels (`START DRILL`, `ARMING…`) and Semantics labels.
  Update the tests that assert on exact button label text to accept
  `COMMIT // START DRILL`.
- Add a visual smoke test: golden file for each restyled screen in light and
  dark. Gate optional — can defer.
- Manual: verify press-and-hold STOP timing unchanged (800ms), arming-failed
  retry still works, Program A group assignment flow unchanged.

## Phasing (for writing-plans to elaborate)

1. Foundations: theme flip, typography, `TacticalAppBar`, `TacticalScaffold`,
   `TacticalGridBackground`, zero radius. App still boots with old layouts
   inside the new shell.
2. Reusable widgets: `TacticalSection`, `TacticalCard`, `TacticalStepper`,
   `TacticalMinMaxCard`, `TacticalPrimaryButton`, `TacticalStatusChip`,
   `TacticalHudTile`, `GroupNodeCard`, `TargetNodeChip`.
3. Screens in order of risk: home → device_discovery → program_b →
   program_a → results → drill_running (last, most safety-sensitive).
4. Delete `IncDec` and `TargetChip` after all call sites migrated.
5. Update tests.

## Open questions

None remaining — all four design forks resolved during brainstorming.
