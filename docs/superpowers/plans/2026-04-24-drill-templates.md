# Drill Templates (Presets) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the DropdownButton preset selector in both setup screens with a scrollable chip strip, add last-used auto-load via `PreferencesRepository.getDefaultPresetId()`, and add a `PresetManagerScreen` accessible from HomeScreen for listing, renaming, and deleting saved presets.

**Architecture:** `DrillTemplateRepository` gains a `rename()` method. A new `PresetChipStrip` widget replaces `PresetRow` in both setup screens; it reads `getDefaultPresetId()` from `PreferencesRepository` on load to auto-select the last-used preset. `PresetManagerScreen` uses the standard `FutureBuilder + didChangeDependencies` pattern; tapping a row writes the preset id to prefs then opens the correct setup screen, where the chip strip picks it up automatically. A swipe-to-reveal gesture exposes REN and DEL actions per row without any new package dependencies.

**Tech Stack:** Flutter/Dart, sqflite, shared_preferences, provider, existing tactical widget library (`TacticalScaffold`, `TacticalCard`, `TacticalSection`, `TacticalPrimaryButton`, `AtriarchTokens`).

---

## File Map

| File | Status | Purpose |
|---|---|---|
| `lib/repositories/drill_template_repository.dart` | **edit** | add `rename()` method |
| `test/repositories/drill_template_repository_test.dart` | **edit** | add `rename()` unit test |
| `test/test_helpers/fake_drill_template_repository.dart` | **edit** | add `rename()` stub |
| `lib/widgets/preset_chip_strip.dart` | **new** | horizontal chip-strip preset selector widget |
| `test/widgets/preset_chip_strip_test.dart` | **new** | widget tests (fake repos, no DB) |
| `lib/screens/program_a_setup_screen.dart` | **edit** | swap PresetRow → PresetChipStrip, write last-used on drill start |
| `lib/screens/program_b_setup_screen.dart` | **edit** | same as Program A |
| `lib/screens/preset_manager_screen.dart` | **new** | browse / rename / delete presets |
| `test/screens/preset_manager_screen_test.dart` | **new** | widget tests (fake repos, no DB) |
| `lib/screens/home_screen.dart` | **edit** | add PRESETS nav button |
| `test/screens/home_screen_presets_test.dart` | **new** | presence + nav test |

---

## Context you need

### Key existing APIs

**`PreferencesRepository`** (at `lib/services/preferences_repository.dart`):
```dart
Future<String?> getDefaultPresetId() async => _prefs.getString(_kDefaultPresetId);
Future<void> setDefaultPresetId(String? id) async { ... }
```
These already exist — no changes needed to `PreferencesRepository`.

**`FakeDrillTemplateRepository`** (at `test/test_helpers/fake_drill_template_repository.dart`):  
Implements `DrillTemplateRepository` interface using an in-memory map. Has `insert`, `upsert`, `getById`, `listAll`, `delete`. Needs `rename()` added in Task 1.

**`AppState`** exposes:
- `state.drillTemplates` → `DrillTemplateRepository?`
- `state.preferences` → `PreferencesRepository?`

**Setup screens**: `ProgramASetupScreen` and `ProgramBSetupScreen` both use `PresetRow` today (see `lib/widgets/preset_row.dart`). Both have `_applyPreset(DrillTemplate)` and `_promptSavePresetName()` methods that stay in place — `PresetChipStrip` calls them via callbacks.

**Widget test constraint**: Never use `DatabaseHelper.openForTesting()` inside a `pumpWidget` call — it deadlocks on macOS. All widget tests use `FakeDrillTemplateRepository` and `FakePreferencesRepository`.

**Test file invocation**: Never run `flutter test test/screens/` (directory form) — macOS resource-fork files crash the runner. Always name the file explicitly.

---

## Task 1: `DrillTemplateRepository.rename()` + fake + test

**Files:**
- Modify: `lib/repositories/drill_template_repository.dart`
- Modify: `test/repositories/drill_template_repository_test.dart`
- Modify: `test/test_helpers/fake_drill_template_repository.dart`

- [ ] **Step 1: Write the failing test**

Append inside the existing `group('DrillTemplateRepository', ...)` block in `test/repositories/drill_template_repository_test.dart`:

```dart
    test('rename updates the template name', () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = DrillTemplateRepository(db);
      await repo.insert(_tpl('r1', 'Old Name'));
      await repo.rename('r1', 'New Name');
      final got = await repo.getById('r1');
      expect(got!.name, 'New Name');
      await db.close();
    });

    test('rename on unknown id is a no-op', () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = DrillTemplateRepository(db);
      await repo.rename('does-not-exist', 'Whatever');
      expect(await repo.listAll(), isEmpty);
      await db.close();
    });
```

- [ ] **Step 2: Run to confirm failure**

```
cd /Volumes/T7/Atriarch && flutter test test/repositories/drill_template_repository_test.dart 2>&1 | tail -5
```

Expected: FAIL — `The method 'rename' isn't defined`.

- [ ] **Step 3: Add `rename()` to `DrillTemplateRepository`**

In `lib/repositories/drill_template_repository.dart`, add after the `delete()` method:

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

- [ ] **Step 4: Add `rename()` stub to `FakeDrillTemplateRepository`**

In `test/test_helpers/fake_drill_template_repository.dart`, add after `delete()`:

```dart
  @override
  Future<void> rename(String id, String newName) async {
    final t = _byId[id];
    if (t == null) return;
    _byId[id] = DrillTemplate(
      id: t.id,
      shooterId: t.shooterId,
      name: newName,
      programType: t.programType,
      config: t.config,
      configHash: t.configHash,
      createdAt: t.createdAt,
    );
  }
```

- [ ] **Step 5: Run — must pass**

```
cd /Volumes/T7/Atriarch && flutter test test/repositories/drill_template_repository_test.dart 2>&1 | tail -5
```

Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```
cd /Volumes/T7/Atriarch && git add lib/repositories/drill_template_repository.dart test/repositories/drill_template_repository_test.dart test/test_helpers/fake_drill_template_repository.dart && git commit -m "$(cat <<'EOF'
feat(templates): add DrillTemplateRepository.rename()

Single UPDATE query. FakeDrillTemplateRepository stub added so widget
tests can exercise rename flows without touching SQLite.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `PresetChipStrip` widget

**Files:**
- Create: `lib/widgets/preset_chip_strip.dart`
- Create: `test/widgets/preset_chip_strip_test.dart`

- [ ] **Step 1: Write the failing widget tests**

```dart
// test/widgets/preset_chip_strip_test.dart
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/drill_template.dart';
import 'package:atriarch/services/config_hasher.dart';
import 'package:atriarch/widgets/preset_chip_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/fake_drill_template_repository.dart';
import '../test_helpers/fake_preferences_repository.dart';

DrillTemplate _tpl(String id, String name,
    {ProgramType type = ProgramType.programA}) {
  final cfg = DrillConfig(programType: type);
  return DrillTemplate(
    id: id,
    shooterId: null,
    name: name,
    programType: type,
    config: cfg,
    configHash: ConfigHasher.hash(cfg),
    createdAt: DateTime(2026),
  );
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('PresetChipStrip', () {
    testWidgets('shows only SAVE chip when no templates', (tester) async {
      final repo = FakeDrillTemplateRepository();
      await tester.pumpWidget(_wrap(
        PresetChipStrip(
          drillTemplates: repo,
          currentConfig: () => DrillConfig(programType: ProgramType.programA),
          onLoad: (_) {},
          onSave: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('+ SAVE'), findsOneWidget);
      expect(find.textContaining('ALPHA'), findsNothing);
    });

    testWidgets('renders a chip for each template', (tester) async {
      final repo = FakeDrillTemplateRepository();
      await repo.insert(_tpl('a', 'ALPHA'));
      await repo.insert(_tpl('b', 'BETA'));
      await tester.pumpWidget(_wrap(
        PresetChipStrip(
          drillTemplates: repo,
          currentConfig: () => DrillConfig(programType: ProgramType.programA),
          onLoad: (_) {},
          onSave: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('ALPHA'), findsOneWidget);
      expect(find.text('BETA'), findsOneWidget);
      expect(find.text('+ SAVE'), findsOneWidget);
    });

    testWidgets('auto-selects chip matching last-used preset id', (tester) async {
      final repo = FakeDrillTemplateRepository();
      await repo.insert(_tpl('a', 'ALPHA'));
      await repo.insert(_tpl('b', 'BETA'));
      final prefs = FakePreferencesRepository();
      await prefs.setDefaultPresetId('b');
      DrillTemplate? loaded;
      await tester.pumpWidget(_wrap(
        PresetChipStrip(
          drillTemplates: repo,
          preferences: prefs,
          currentConfig: () => DrillConfig(programType: ProgramType.programA),
          onLoad: (t) => loaded = t,
          onSave: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(loaded?.id, 'b');
    });

    testWidgets('tapping a chip calls onLoad with that template', (tester) async {
      final repo = FakeDrillTemplateRepository();
      await repo.insert(_tpl('a', 'ALPHA'));
      DrillTemplate? loaded;
      await tester.pumpWidget(_wrap(
        PresetChipStrip(
          drillTemplates: repo,
          currentConfig: () => DrillConfig(programType: ProgramType.programA),
          onLoad: (t) => loaded = t,
          onSave: () {},
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALPHA'));
      await tester.pump();
      expect(loaded?.id, 'a');
    });

    testWidgets('shows LOADED label when last-used preset auto-selected',
        (tester) async {
      final repo = FakeDrillTemplateRepository();
      await repo.insert(_tpl('a', 'ALPHA'));
      final prefs = FakePreferencesRepository();
      await prefs.setDefaultPresetId('a');
      await tester.pumpWidget(_wrap(
        PresetChipStrip(
          drillTemplates: repo,
          preferences: prefs,
          currentConfig: () => DrillConfig(programType: ProgramType.programA),
          onLoad: (_) {},
          onSave: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('LOADED'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run to confirm failure**

```
cd /Volumes/T7/Atriarch && flutter test test/widgets/preset_chip_strip_test.dart 2>&1 | tail -5
```

Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Implement `lib/widgets/preset_chip_strip.dart`**

```dart
// lib/widgets/preset_chip_strip.dart
import 'package:flutter/material.dart';

import '../models/drill_config.dart';
import '../models/drill_template.dart';
import '../repositories/drill_template_repository.dart';
import '../services/preferences_repository.dart';
import '../theme/atriarch_theme.dart';
import 'tactical/tactical_card.dart';

/// Horizontal scrollable chip strip for selecting a saved drill preset.
///
/// Replaces the DropdownButton-based [PresetRow] in setup screens.
/// Reads [PreferencesRepository.getDefaultPresetId] on init to auto-select
/// the last-used preset and call [onLoad] with it.
class PresetChipStrip extends StatefulWidget {
  const PresetChipStrip({
    super.key,
    required this.drillTemplates,
    required this.currentConfig,
    required this.onLoad,
    required this.onSave,
    this.preferences,
    this.onSelectionChanged,
  });

  final DrillTemplateRepository drillTemplates;
  final DrillConfig Function() currentConfig;
  final void Function(DrillTemplate) onLoad;
  final VoidCallback onSave;
  final PreferencesRepository? preferences;
  final void Function(DrillTemplate?)? onSelectionChanged;

  @override
  State<PresetChipStrip> createState() => _PresetChipStripState();
}

class _PresetChipStripState extends State<PresetChipStrip> {
  List<DrillTemplate> _templates = const [];
  DrillTemplate? _selected;
  bool _loadedFromPrefs = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final templates = await widget.drillTemplates.listAll();
    String? lastId;
    if (widget.preferences != null) {
      lastId = await widget.preferences!.getDefaultPresetId();
    }
    if (!mounted) return;
    DrillTemplate? selected;
    bool fromPrefs = false;
    if (lastId != null) {
      try {
        selected = templates.firstWhere((t) => t.id == lastId);
        fromPrefs = true;
      } catch (_) {
        // lastId no longer exists — ignore
      }
    }
    setState(() {
      _templates = templates;
      _selected = selected;
      _loadedFromPrefs = fromPrefs;
      _loading = false;
    });
    if (selected != null) {
      widget.onLoad(selected);
      widget.onSelectionChanged?.call(selected);
    }
  }

  Future<void> _refresh() async {
    final templates = await widget.drillTemplates.listAll();
    if (!mounted) return;
    setState(() {
      _templates = templates;
      if (_selected != null && !templates.any((t) => t.id == _selected!.id)) {
        _selected = null;
        _loadedFromPrefs = false;
        widget.onSelectionChanged?.call(null);
      }
    });
  }

  void _onSavePressed() {
    widget.onSave();
    Future<void>.delayed(const Duration(milliseconds: 80), _refresh);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    if (_loading) {
      return TacticalCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AtriarchSpacing.md,
          vertical: AtriarchSpacing.sm,
        ),
        child: const SizedBox(
          height: 32,
          child: Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    return TacticalCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AtriarchSpacing.md,
        vertical: AtriarchSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_loadedFromPrefs && _selected != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AtriarchSpacing.xs),
              child: Text(
                'LOADED: ${_selected!.name}',
                style: AtriarchText.labelTiny(color: tokens.textTertiary),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in _templates)
                  _Chip(
                    label: t.name,
                    selected: _selected?.id == t.id,
                    onTap: () {
                      setState(() {
                        _selected = t;
                        _loadedFromPrefs = false;
                      });
                      widget.onLoad(t);
                      widget.onSelectionChanged?.call(t);
                    },
                  ),
                _Chip(
                  label: '+ SAVE',
                  selected: false,
                  onTap: _onSavePressed,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: AtriarchSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AtriarchSpacing.sm,
          vertical: AtriarchSpacing.xs,
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? tokens.statusHit : tokens.border,
          ),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          label,
          style: AtriarchText.labelTiny(
            color: selected ? tokens.statusHit : tokens.textTertiary,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run — must pass**

```
cd /Volumes/T7/Atriarch && flutter test test/widgets/preset_chip_strip_test.dart 2>&1 | tail -5
```

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```
cd /Volumes/T7/Atriarch && git add lib/widgets/preset_chip_strip.dart test/widgets/preset_chip_strip_test.dart && git commit -m "$(cat <<'EOF'
feat(widgets): add PresetChipStrip — tactical horizontal chip preset selector

Replaces DropdownButton-based PresetRow. Reads last-used preset id from
PreferencesRepository on load; shows LOADED banner when auto-selected.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Swap PresetRow → PresetChipStrip in both setup screens

**Files:**
- Modify: `lib/screens/program_a_setup_screen.dart`
- Modify: `lib/screens/program_b_setup_screen.dart`

This task has no new tests — the chip strip behaviour is covered by Task 2 tests, and the setup screens are covered by their existing phase-listener / BLE integration tests. The steps below include a compile+run check.

### Program A Setup Screen

- [ ] **Step 1: Replace import in `program_a_setup_screen.dart`**

Find this line near the top imports:
```dart
import '../widgets/preset_row.dart';
```
Replace with:
```dart
import '../widgets/preset_chip_strip.dart';
```

- [ ] **Step 2: Add `_selectedTemplate` field to `_ProgramASetupScreenState`**

Find the class-level fields (near `startMinCtrl`, `iterCtrl`, etc.). Add:
```dart
  DrillTemplate? _selectedTemplate;
```

- [ ] **Step 3: Replace the `PresetRow(...)` Consumer block with `PresetChipStrip`**

Find this block in the `build` method:
```dart
          Consumer<AppState>(
            builder: (_, state, __) {
              final repo = state.drillTemplates;
              if (repo == null) return const SizedBox.shrink();
              return PresetRow(
                drillTemplates: repo,
                currentConfig: _currentConfigSnapshot,
                onLoad: _applyPreset,
                onSave: _promptSavePresetName,
              );
            },
          ),
```

Replace with:
```dart
          Consumer<AppState>(
            builder: (_, state, __) {
              final repo = state.drillTemplates;
              if (repo == null) return const SizedBox.shrink();
              return PresetChipStrip(
                drillTemplates: repo,
                preferences: state.preferences,
                currentConfig: _currentConfigSnapshot,
                onLoad: _applyPreset,
                onSave: _promptSavePresetName,
                onSelectionChanged: (t) =>
                    setState(() => _selectedTemplate = t),
              );
            },
          ),
```

- [ ] **Step 4: Make `_startDrill` write last-used preset id**

Find the existing `_startDrill` method:
```dart
  void _startDrill() {
    final config = _buildConfig();
    if (config == null) return;
    _lastConfig = config;
    context.read<AppState>().startDrill(config);
  }
```

Replace with:
```dart
  Future<void> _startDrill() async {
    final config = _buildConfig();
    if (config == null) return;
    _lastConfig = config;
    final state = context.read<AppState>();
    if (_selectedTemplate != null) {
      await state.preferences?.setDefaultPresetId(_selectedTemplate!.id);
    }
    if (mounted) state.startDrill(config);
  }
```

### Program B Setup Screen

Repeat the same four steps for `lib/screens/program_b_setup_screen.dart`. The code is identical except the class name is `_ProgramBSetupScreenState`.

- [ ] **Step 5: Replace import** (same as Program A Step 1)

- [ ] **Step 6: Add `_selectedTemplate` field** (same as Program A Step 2)

- [ ] **Step 7: Replace PresetRow Consumer block** (same as Program A Step 3)

- [ ] **Step 8: Make `_startDrill` async with last-used write** (same as Program A Step 4)

- [ ] **Step 9: Verify no analysis errors**

```
cd /Volumes/T7/Atriarch && flutter analyze lib/screens/program_a_setup_screen.dart lib/screens/program_b_setup_screen.dart 2>&1 | tail -10
```

Expected: `No issues found!` (or only pre-existing infos, no new errors/warnings)

- [ ] **Step 10: Commit**

```
cd /Volumes/T7/Atriarch && git add lib/screens/program_a_setup_screen.dart lib/screens/program_b_setup_screen.dart && git commit -m "$(cat <<'EOF'
feat(setup): swap PresetRow for PresetChipStrip in both setup screens

Passes preferences repo for last-used auto-load. Tracks selected template
in _selectedTemplate field; writes setDefaultPresetId on drill start.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `PresetManagerScreen`

**Files:**
- Create: `lib/screens/preset_manager_screen.dart`
- Create: `test/screens/preset_manager_screen_test.dart`

- [ ] **Step 1: Write failing widget tests**

```dart
// test/screens/preset_manager_screen_test.dart
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/drill_template.dart';
import 'package:atriarch/screens/preset_manager_screen.dart';
import 'package:atriarch/services/config_hasher.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_drill_template_repository.dart';
import '../test_helpers/fake_preferences_repository.dart';

DrillTemplate _tpl(String id, String name,
    {ProgramType type = ProgramType.programA}) {
  final cfg = DrillConfig(programType: type);
  return DrillTemplate(
    id: id,
    shooterId: null,
    name: name,
    programType: type,
    config: cfg,
    configHash: ConfigHasher.hash(cfg),
    createdAt: DateTime(2026),
  );
}

Widget _wrap(Widget child,
    {FakeDrillTemplateRepository? repo,
    FakePreferencesRepository? prefs}) {
  return MaterialApp(
    home: ChangeNotifierProvider<AppState>(
      create: (_) => AppState(
        drillTemplates: repo ?? FakeDrillTemplateRepository(),
        preferences: prefs ?? FakePreferencesRepository(),
      ),
      child: child,
    ),
  );
}

void main() {
  group('PresetManagerScreen', () {
    testWidgets('shows empty state when no presets', (tester) async {
      await tester.pumpWidget(_wrap(const PresetManagerScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('NO PRESETS'), findsOneWidget);
    });

    testWidgets('renders a row for each preset', (tester) async {
      final repo = FakeDrillTemplateRepository();
      await repo.insert(_tpl('a', 'ALPHA'));
      await repo.insert(_tpl('b', 'BETA'));
      await tester.pumpWidget(_wrap(const PresetManagerScreen(), repo: repo));
      await tester.pumpAndSettle();
      expect(find.textContaining('ALPHA'), findsOneWidget);
      expect(find.textContaining('BETA'), findsOneWidget);
    });

    testWidgets('shows program type badge per row', (tester) async {
      final repo = FakeDrillTemplateRepository();
      await repo.insert(_tpl('a', 'ALPHA', type: ProgramType.programA));
      await repo.insert(_tpl('b', 'BETA', type: ProgramType.programB));
      await tester.pumpWidget(_wrap(const PresetManagerScreen(), repo: repo));
      await tester.pumpAndSettle();
      expect(find.textContaining('PGM-A'), findsOneWidget);
      expect(find.textContaining('PGM-B'), findsOneWidget);
    });

    testWidgets('delete removes the preset from the list', (tester) async {
      final repo = FakeDrillTemplateRepository();
      await repo.insert(_tpl('a', 'ALPHA'));
      await tester.pumpWidget(_wrap(const PresetManagerScreen(), repo: repo));
      await tester.pumpAndSettle();

      // Swipe the row left to reveal DEL button
      await tester.drag(find.textContaining('ALPHA'), const Offset(-200, 0));
      await tester.pumpAndSettle();

      // Tap DEL
      await tester.tap(find.text('DEL'));
      await tester.pumpAndSettle();

      // Confirm in dialog
      await tester.tap(find.text('DELETE'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ALPHA'), findsNothing);
      expect(find.textContaining('NO PRESETS'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run to confirm failure**

```
cd /Volumes/T7/Atriarch && flutter test test/screens/preset_manager_screen_test.dart 2>&1 | tail -5
```

Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Implement `lib/screens/preset_manager_screen.dart`**

```dart
// lib/screens/preset_manager_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/drill_config.dart';
import '../models/drill_template.dart';
import '../repositories/drill_template_repository.dart';
import '../services/preferences_repository.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';
import 'program_a_setup_screen.dart';
import 'program_b_setup_screen.dart';

class PresetManagerScreen extends StatefulWidget {
  const PresetManagerScreen({super.key});

  @override
  State<PresetManagerScreen> createState() => _PresetManagerScreenState();
}

class _PresetManagerScreenState extends State<PresetManagerScreen> {
  Future<List<DrillTemplate>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<DrillTemplate>> _load() async {
    final repo = context.read<AppState>().drillTemplates;
    if (repo == null) return const [];
    return repo.listAll();
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _rename(
      BuildContext ctx, DrillTemplateRepository repo, DrillTemplate t) async {
    final controller = TextEditingController(text: t.name);
    final newName = await showDialog<String>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Rename preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'Preset name',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogCtx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == t.name) return;
    await repo.rename(t.id, newName);
    _refresh();
  }

  Future<void> _delete(BuildContext ctx, DrillTemplateRepository repo,
      PreferencesRepository? prefs, DrillTemplate t) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete preset?'),
        content: Text('Delete "${t.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repo.delete(t.id);
    // Clear last-used if it was this preset
    final lastId = await prefs?.getDefaultPresetId();
    if (lastId == t.id) await prefs?.setDefaultPresetId(null);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return TacticalScaffold(
      title: 'PRESETS',
      body: FutureBuilder<List<DrillTemplate>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data ?? const [];
          if (data.isEmpty) {
            final tokens = context.atriarch;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AtriarchSpacing.lg),
                child: Text(
                  'NO PRESETS SAVED.\nSave a preset from Program A or B setup.',
                  style: AtriarchText.labelTiny(color: tokens.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _ManagerBody(
            templates: data,
            onRename: (t) {
              final state = context.read<AppState>();
              final repo = state.drillTemplates;
              if (repo == null) return;
              _rename(context, repo, t);
            },
            onDelete: (t) {
              final state = context.read<AppState>();
              final repo = state.drillTemplates;
              if (repo == null) return;
              _delete(context, repo, state.preferences, t);
            },
            onTap: (t) async {
              final state = context.read<AppState>();
              await state.preferences?.setDefaultPresetId(t.id);
              if (!mounted) return;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => t.programType == ProgramType.programA
                      ? const ProgramASetupScreen()
                      : const ProgramBSetupScreen(),
                ),
              );
              _refresh();
            },
          );
        },
      ),
    );
  }
}

class _ManagerBody extends StatelessWidget {
  final List<DrillTemplate> templates;
  final void Function(DrillTemplate) onRename;
  final void Function(DrillTemplate) onDelete;
  final void Function(DrillTemplate) onTap;

  const _ManagerBody({
    required this.templates,
    required this.onRename,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AtriarchSpacing.lg),
      children: [
        const TacticalSection(code: 'PST_01', trailing: 'SAVED PRESETS'),
        const SizedBox(height: AtriarchSpacing.sm),
        for (final t in templates)
          _SwipeablePresetRow(
            template: t,
            onTap: () => onTap(t),
            onRename: () => onRename(t),
            onDelete: () => onDelete(t),
          ),
        const SizedBox(height: AtriarchSpacing.xxl),
      ],
    );
  }
}

class _SwipeablePresetRow extends StatefulWidget {
  final DrillTemplate template;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _SwipeablePresetRow({
    required this.template,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_SwipeablePresetRow> createState() => _SwipeablePresetRowState();
}

class _SwipeablePresetRowState extends State<_SwipeablePresetRow>
    with SingleTickerProviderStateMixin {
  static const double _kRevealWidth = 110.0;
  late final AnimationController _snapController;
  late Animation<double> _snapAnimation;
  double _offset = 0.0;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _snapAnimation = Tween<double>(begin: 0, end: 0).animate(_snapController);
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _snapTo(double target) {
    final start = _offset;
    _snapAnimation = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOut),
    )..addListener(() => setState(() => _offset = _snapAnimation.value));
    _snapController
      ..reset()
      ..forward();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _snapController.stop();
    setState(() =>
        _offset = (_offset + d.delta.dx).clamp(-_kRevealWidth, 0.0));
  }

  void _onDragEnd(DragEndDetails d) {
    final shouldOpen = _offset < -_kRevealWidth / 2 ||
        (d.primaryVelocity ?? 0) < -300;
    _snapTo(shouldOpen ? -_kRevealWidth : 0.0);
  }

  void _close() => _snapTo(0.0);

  String _configSummary(DrillTemplate t) {
    final c = t.config;
    return '${c.iterations} ITER · '
        '${c.startMin.toStringAsFixed(1)}–${c.startMax.toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final t = widget.template;
    final pgm = t.programType == ProgramType.programA ? 'PGM-A' : 'PGM-B';

    return Padding(
      padding: const EdgeInsets.only(bottom: AtriarchSpacing.xs),
      child: ClipRect(
        child: GestureDetector(
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onTap: _offset != 0.0 ? _close : widget.onTap,
          child: Stack(
            children: [
              // Action tiles (revealed on swipe left)
              Positioned.fill(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () {
                        _close();
                        widget.onRename();
                      },
                      child: Container(
                        width: 55,
                        color: tokens.textPrimary.withOpacity(0.12),
                        alignment: Alignment.center,
                        child: Text(
                          'REN',
                          style: AtriarchText.labelTiny(
                              color: tokens.textPrimary),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        _close();
                        widget.onDelete();
                      },
                      child: Container(
                        width: 55,
                        color: tokens.statusViolation.withOpacity(0.2),
                        alignment: Alignment.center,
                        child: Text(
                          'DEL',
                          style: AtriarchText.labelTiny(
                              color: tokens.statusViolation),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Main row (slides left to reveal actions)
              Transform.translate(
                offset: Offset(_offset, 0),
                child: Material(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AtriarchSpacing.md,
                      vertical: AtriarchSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.name,
                                style: AtriarchText.labelTiny(
                                    color: tokens.statusHit),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$pgm · ${_configSummary(t)}',
                                style: AtriarchText.labelTiny(
                                    color: tokens.textTertiary),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '›',
                          style: TextStyle(
                              color: tokens.textTertiary, fontSize: 18),
                        ),
                      ],
                    ),
                  ),
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

- [ ] **Step 4: Run — must pass**

```
cd /Volumes/T7/Atriarch && flutter test test/screens/preset_manager_screen_test.dart 2>&1 | tail -5
```

Expected: `All tests passed!`

If the delete test fails because the swipe gesture doesn't move far enough for the test viewport, try increasing the drag offset: replace `const Offset(-200, 0)` with `const Offset(-300, 0)`.

- [ ] **Step 5: Commit**

```
cd /Volumes/T7/Atriarch && git add lib/screens/preset_manager_screen.dart test/screens/preset_manager_screen_test.dart && git commit -m "$(cat <<'EOF'
feat(screens): add PresetManagerScreen with swipe-to-reveal REN/DEL

Lists all saved presets; tap opens matching setup screen pre-loaded via
setDefaultPresetId. Swipe left reveals rename and delete action tiles.
No new package dependencies — custom GestureDetector + AnimationController.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: HomeScreen PRESETS entry

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Create: `test/screens/home_screen_presets_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/screens/home_screen_presets_test.dart
import 'package:atriarch/screens/home_screen.dart';
import 'package:atriarch/screens/preset_manager_screen.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_drill_template_repository.dart';
import '../test_helpers/fake_preferences_repository.dart';

Widget _wrapHome() {
  final prefs = FakePreferencesRepository();
  return MaterialApp(
    home: ChangeNotifierProvider<AppState>(
      create: (_) {
        final state = AppState(
          preferences: prefs,
          drillTemplates: FakeDrillTemplateRepository(),
        );
        state.setOnboardingCompleteForTesting(true);
        return state;
      },
      child: const HomeScreen(),
    ),
  );
}

void main() {
  group('HomeScreen PRESETS entry', () {
    testWidgets('PRESETS button is present', (tester) async {
      await tester.pumpWidget(_wrapHome());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('PRESETS'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('PRESETS'), findsOneWidget);
    });

    testWidgets('tapping PRESETS navigates to PresetManagerScreen',
        (tester) async {
      await tester.pumpWidget(_wrapHome());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('PRESETS'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('PRESETS'));
      await tester.pumpAndSettle();
      expect(find.byType(PresetManagerScreen), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run to confirm failure**

```
cd /Volumes/T7/Atriarch && flutter test test/screens/home_screen_presets_test.dart 2>&1 | tail -5
```

Expected: FAIL — `PRESETS` not found.

- [ ] **Step 3: Add PRESETS button to HomeScreen UTILITIES section**

In `lib/screens/home_screen.dart`, add the import near the other screen imports:
```dart
import 'preset_manager_screen.dart';
```

Then find the UTILITIES section. Currently:
```dart
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalPrimaryButton(
            label: 'TARGET_BREAKDOWN',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TargetBreakdownScreen()),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalPrimaryButton(
            label: 'SETTINGS',
```

Insert after TARGET_BREAKDOWN:
```dart
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalPrimaryButton(
            label: 'PRESETS',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PresetManagerScreen()),
            ),
          ),
```

- [ ] **Step 4: Run — must pass**

```
cd /Volumes/T7/Atriarch && flutter test test/screens/home_screen_presets_test.dart 2>&1 | tail -5
```

Expected: `All tests passed!`

- [ ] **Step 5: Run full regression suite**

```
cd /Volumes/T7/Atriarch && flutter test test/repositories/drill_template_repository_test.dart test/widgets/preset_chip_strip_test.dart test/screens/preset_manager_screen_test.dart test/screens/home_screen_presets_test.dart test/screens/results_screen_test.dart test/services/metrics_engine_test.dart 2>&1 | tail -5
```

Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```
cd /Volumes/T7/Atriarch && git add lib/screens/home_screen.dart test/screens/home_screen_presets_test.dart && git commit -m "$(cat <<'EOF'
feat(nav): add PRESETS entry to HomeScreen UTILITIES section

Navigates to PresetManagerScreen for browsing, renaming, and deleting
saved drill presets.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Self-review checklist

| Requirement | Task |
|---|---|
| `DrillTemplateRepository.rename()` method | Task 1 |
| `FakeDrillTemplateRepository.rename()` stub | Task 1 |
| `PresetChipStrip` — horizontal chips, green when selected | Task 2 |
| Last-used auto-select via `getDefaultPresetId()` | Task 2 |
| `LOADED: <name>` banner when auto-selected | Task 2 |
| `+ SAVE` chip at end of strip | Task 2 |
| Swap `PresetRow` → `PresetChipStrip` in Program A setup | Task 3 |
| Swap `PresetRow` → `PresetChipStrip` in Program B setup | Task 3 |
| Write `setDefaultPresetId` on drill start | Task 3 |
| `PresetManagerScreen` — FutureBuilder + didChangeDependencies | Task 4 |
| Empty state `NO PRESETS SAVED.` | Task 4 |
| `_SwipeablePresetRow` — swipe left reveals REN + DEL | Task 4 |
| Tap row → writes preset id to prefs → opens correct setup screen | Task 4 |
| Rename dialog pre-filled with current name | Task 4 |
| Delete clears last-used if it was the deleted preset | Task 4 |
| `PRESETS` button in HomeScreen UTILITIES | Task 5 |
| All widget tests use fake repos (no sqflite FFI deadlock) | All tasks |
| TDD: tests written before implementation | All tasks |
