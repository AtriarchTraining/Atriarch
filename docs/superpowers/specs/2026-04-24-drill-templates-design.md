# Drill Templates (Presets) Design

**Goal:** Fix the tactical aesthetic of the preset selector in setup screens, add last-used auto-load, and provide a standalone management screen for browsing, renaming, and deleting saved presets.

**Architecture:** Thin additions to existing infrastructure. `DrillTemplate`, `DrillTemplateRepository`, and the `drill_templates` SQLite table already exist. The work is: (1) a new `PresetChipStrip` widget replacing the existing `DropdownButton`-based `PresetRow`, (2) last-used tracking via `PreferencesRepository`, (3) a new `PresetManagerScreen`, and (4) HomeScreen wiring.

**Tech Stack:** Flutter/Dart, sqflite, shared_preferences, provider, existing tactical widget library (`TacticalScaffold`, `TacticalCard`, `TacticalPrimaryButton`, `AtriarchTokens`).

---

## Data Layer

### `DrillTemplateRepository.rename()`

Add one method — no schema change or migration needed:

```dart
Future<void> rename(String id, String newName) async {
  await _db.update(
    'drill_templates',
    {'name': newName},
    where: 'id = ?',
    whereArgs: [id],
  );
}
```

### `PreferencesRepository.lastTemplateId`

Add getter/setter to the existing `PreferencesRepository` (which already stores the 8h session cutoff):

```dart
static const _kLastTemplateId = 'last_template_id';

// SharedPreferences is loaded once on app init — getter is synchronous.
String? get lastTemplateId => _prefs.getString(_kLastTemplateId);

Future<void> setLastTemplateId(String? id) async {
  if (id == null) {
    await _prefs.remove(_kLastTemplateId);
  } else {
    await _prefs.setString(_kLastTemplateId, id);
  }
}
```

---

## `PresetChipStrip` Widget

**File:** `lib/widgets/preset_chip_strip.dart`

Replaces `PresetRow` in `ProgramASetupScreen` and `ProgramBSetupScreen`.

**Interface:**

```dart
class PresetChipStrip extends StatefulWidget {
  const PresetChipStrip({
    super.key,
    required this.drillTemplates,
    required this.currentConfig,
    required this.onLoad,
    required this.onSave,
    this.initialTemplateId,
  });

  final DrillTemplateRepository drillTemplates;
  final DrillConfig Function() currentConfig;
  final void Function(DrillTemplate) onLoad;
  final VoidCallback onSave;
  final String? initialTemplateId;
}
```

**Behavior:**

- `initState` calls `listAll()` and pre-selects the chip matching `initialTemplateId` if provided
- Renders a `TacticalCard` containing a horizontal `SingleChildScrollView` of chips
- Unselected chip: neutral border, `textTertiary` label
- Selected chip: `statusHit` (green) border + text
- `+ SAVE` chip at the far right — tapping opens the existing name dialog, then calls `onSave()` and refreshes the list after a 50ms beat
- When `initialTemplateId` is non-null and matched, shows a `LOADED: <name>` label in `textTertiary` above the strip (one line, `AtriarchText.labelTiny`)

**Setup screen integration:**

- `didChangeDependencies` reads `state.preferences?.lastTemplateId` and passes it as `initialTemplateId`
- When the user taps ARM/START, write `state.preferences?.setLastTemplateId(selectedTemplate?.id)` before navigating to `DrillRunningScreen`
- Only write if there is a selected template; if the user runs with no preset selected, leave the stored id unchanged

---

## `PresetManagerScreen`

**File:** `lib/screens/preset_manager_screen.dart`

**Pattern:** `StatefulWidget` + `didChangeDependencies` + `FutureBuilder` (matches all other analytics screens).

**Structure:**

```
TacticalScaffold(title: 'PRESETS')
└── FutureBuilder<List<DrillTemplate>>
    ├── loading → CircularProgressIndicator
    ├── empty  → centered 'NO PRESETS SAVED.' (AtriarchText.labelTiny, textTertiary)
    └── data   → ListView of _SwipeablePresetRow
```

**`_SwipeablePresetRow` (private widget, same file):**

- Custom swipe-to-reveal: `GestureDetector` + `AnimationController` (200ms snap) + `Transform.translate`
- Swipe left reveals two action tiles behind the row:
  - `REN` — `textPrimary` (white) accent; tapping opens a `showDialog` with a `TextField` pre-filled with the current name; on confirm calls `repo.rename()` then `_refresh()`
  - `DEL` — `statusViolation` (red); tapping opens a confirm dialog; on confirm calls `repo.delete()` then `_refresh()`
- Tapping the row body (no swipe in progress): `Navigator.push` to `ProgramASetupScreen` or `ProgramBSetupScreen` based on `template.programType`, with the template pre-loaded; calls `_refresh()` on return
- Row content: preset name (`statusHit` green, `AtriarchText.labelTiny`), `PGM-A` / `PGM-B` badge (`textTertiary`), config summary string (e.g. `5 ITER · 1.0–3.0s`)

**Config summary helper:**

```dart
String _configSummary(DrillTemplate t) {
  final c = t.config;
  return '${c.iterations} ITER · ${c.startMin}–${c.startMax}s';
}
```

**Refresh on return:** Use `await Navigator.push(...)` then call `setState(() { _future = _load(); })` to re-run the future.

---

## HomeScreen Wiring

Add to the UTILITIES section of `lib/screens/home_screen.dart`, after `TARGET_BREAKDOWN` and before `SETTINGS`:

```dart
import 'preset_manager_screen.dart';

// In the ListView children:
const SizedBox(height: AtriarchSpacing.sm),
TacticalPrimaryButton(
  label: 'PRESETS',
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const PresetManagerScreen()),
  ),
),
```

---

## File Map

| File | Status | Purpose |
|---|---|---|
| `lib/repositories/drill_template_repository.dart` | **edit** | add `rename()` method |
| `lib/repositories/preferences_repository.dart` | **edit** | add `lastTemplateId` getter/setter |
| `lib/widgets/preset_chip_strip.dart` | **new** | chip-strip preset selector |
| `lib/screens/program_a_setup_screen.dart` | **edit** | swap PresetRow → PresetChipStrip, write lastTemplateId on drill start |
| `lib/screens/program_b_setup_screen.dart` | **edit** | same as Program A |
| `lib/screens/preset_manager_screen.dart` | **new** | management screen |
| `lib/screens/home_screen.dart` | **edit** | add PRESETS nav entry |
| `test/repositories/drill_template_repository_test.dart` | **edit** | add rename() tests |
| `test/repositories/preferences_repository_test.dart` | **edit** | add lastTemplateId tests |
| `test/widgets/preset_chip_strip_test.dart` | **new** | widget tests (fake repo) |
| `test/screens/preset_manager_screen_test.dart` | **new** | widget tests (fake repo) |
| `test/screens/home_screen_presets_test.dart` | **new** | PRESETS button + nav test |

---

## Testing Strategy

- **Unit tests** (`DrillTemplateRepository.rename`, `PreferencesRepository.lastTemplateId`): use `DatabaseHelper.openForTesting()` — real SQLite, no widget pump
- **Widget tests** (`PresetChipStrip`, `PresetManagerScreen`, HomeScreen): use a `FakeDrillTemplateRepository` (same pattern as `FakeMetricsRepository`) — no sqflite FFI, no deadlock
- `FakeDrillTemplateRepository` seeded via constructor `templates` param; implements `listAll`, `rename`, `delete`, `upsert`
