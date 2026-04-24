# Stage 3: Gate-2 Integration Implementation Plan (Phases 2–5)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land gate-2-work's 10 commits onto `feature/system-v2` reconciled against the tactical + SQLite foundation. Preserve all 6 safety-critical fixes from `e7f926b`. Ship in 4 atomic-commit phases.

**Architecture:** Merge `gate-2-work` with `--no-commit`, then systematically replace Hive-backed data-layer files with SQLite/shared_preferences equivalents (per gates locked in `2026-04-21-stage-3-gate2-integration.md`). Retrofit screens to tactical. Rewrite gate-2 tests on fake-repo pattern. Merge back.

**Tech Stack:** Flutter 3.41 · Dart 3.11 · `sqflite` + SQLite for domain data · `shared_preferences` for UI settings · `flutter_tts` (walk-the-range) · `just_audio` + `audio_session` (ready chime) · Provider · Tactical widget library (already on branch).

**Source worktree:** `/Volumes/T7/Atriarch/.worktrees/stage-3-integration` on `feature/stage-3-integration` (off `feature/system-v2@58a98c9`).

**Reference worktree (READ-ONLY):** `/Volumes/T7/Atriarch/.worktrees/gate-2` on `gate-2-work`. Consult for file contents you need to port.

**Prerequisites already complete (Phase 1):**
- Worktree created.
- `flutter pub get` ran successfully.
- `flutter test` baseline: 90/90 passing.
- `flutter analyze`: 0 issues.
- All 6 safety-critical signatures from `e7f926b` verified in lib/.
- `._*` macOS sidecar files removed.
- Prep commit `99d04a1` — `GeneratedPluginRegistrant.swift` regenerated for sqflite_darwin.
- Spec gates committed in `d8c7dee`.

---

## Constraints (re-read before starting each task)

1. **Safety-critical signatures from `e7f926b` must survive every refactor:**
   - `_phase != DrillPhase.running && _phase != DrillPhase.arming` in `AppState.stopDrill()` (`lib/state/app_state.dart`).
   - `service.uuid.str128.toLowerCase()` and `char.uuid.str128.toLowerCase()` in `lib/services/ble_service.dart`.
   - `state.removeListener(_onPhaseChanged)` before `Navigator.pushReplacement` in `program_a_setup_screen.dart` + `program_b_setup_screen.dart`.
   - `state.removeListener(_checkDrillComplete)` before nav in `drill_running_screen.dart`.
   - `Timer(const Duration(seconds: 8), …)` scan timeout + SNAP reconcile in `AppState`.
   - 800ms hold STOP `Listener` + `AnimationController(duration: Duration(milliseconds: 800))` + `PopScope(canPop: false)` in `drill_running_screen.dart`.
   - `state.discoverTargets()` callable from Program B setup (via `PARAM_00 // NODE_SCAN` button).

   **After any change touching `screens/program_*`, `screens/drill_running_screen`, `services/ble_service`, or `state/app_state`:** re-run the grep sweep in Task 2.0 before committing.

2. **Widget tests never call `DatabaseHelper.openForTesting()` or `sqflite_common_ffi`.** They deadlock on macOS. Use fake repos (see `test/test_helpers/fake_shooter_repo.dart` for the reference pattern).

3. **SQLite for domain data; shared_preferences for UI settings.** Don't backslide.

4. **`firmware/target_accel_test/` is untracked user work — never touch it.**

5. **Metrics derive from ACT/HIT/DONE timestamps**, not from a shot-timer.

---

## File Structure (after all phases complete)

### Created

- `lib/models/drill_template.dart` — domain class for a saved drill config.
- `lib/repositories/drill_template_repository.dart` — SQLite CRUD over `drill_templates` table.
- `lib/services/range_session_view.dart` — derived view over `sessions` table + 8h cutoff.
- `lib/services/preferences_repository.dart` — thin shared_preferences wrapper (replaces gate-2's Hive version).
- `lib/services/audio_service.dart` — ready-chime wrapper over `just_audio` (ported from gate-2).
- `lib/services/tts_port.dart` — abstraction over `flutter_tts` for walk-the-range (ported from gate-2).
- `lib/util/target_name_resolver.dart` — resolves target display names from storage (ported).
- `lib/widgets/preset_row.dart` — tactical-styled preset selector (ported + restyled).
- `lib/widgets/target_actions_sheet.dart` — long-press action sheet (ported + restyled).
- `lib/widgets/drill_share_sheet.dart` — share-drill UI (ported + restyled, driven by events now).
- `lib/widgets/drill_result_image.dart` — drill-result card image (ported + restyled).
- `lib/screens/settings_screen.dart` — tactical scaffold, no theme toggle.
- `lib/screens/recent_drills_screen.dart` — tactical list, driven by RangeSessionView.
- `lib/screens/onboarding/*.dart` — 5 tactical-scaffold step files.
- `test/test_helpers/fake_preferences_repository.dart`
- `test/test_helpers/fake_drill_template_repository.dart`
- `test/test_helpers/fake_audio_service.dart`
- `test/test_helpers/recording_tts_port.dart` (ported from gate-2 tests)
- Test files mirroring each new/ported `lib/` file.

### Modified

- `lib/state/app_state.dart` — add `preferences`, `audio`, `tts`, `rangeSessionView`, `drillTemplates`, `onboardingComplete`, `targetNames`, `removedTargetIds`. All gate-2 additions coexist with plan-1's existing `_sessions`, `_shooterState`, `_batcher`, `_activeDbSessionId`, `_iterationsCompleted`. Preserve STOP-flood guard + 8s scan timeout + SNAP reconcile.
- `lib/theme/theme_controller.dart` — strip `ThemePreference.light` and `ThemePreference.auto`. Enum collapses to `dark` only, or controller is deleted and `MaterialApp` uses a hard-coded `ThemeMode.dark`.
- `lib/main.dart` — drop Hive init, wire new services, register assets for `ready.mp3`.
- `lib/repositories/session_repository.dart` — add `getEventsFor(String sessionId)`.
- `lib/screens/home_screen.dart` — merge tactical styling with gate-2 nav entries (Settings, Recent Drills, Walk-the-Range).
- `lib/screens/program_a_setup_screen.dart` — 3-way: tactical + ShooterChip + PresetRow + target-actions long-press.
- `lib/screens/program_b_setup_screen.dart` — 3-way: same pattern.
- `lib/screens/drill_running_screen.dart` — preserve all safety-critical fixes; no layout conflict expected.
- `lib/screens/results_screen.dart` — add share-sheet entry point in tactical footer.
- `pubspec.yaml` — drop `hive`, `hive_flutter`, `hive_generator`. Add `flutter_tts`, `just_audio`, `audio_session`. Add asset declaration for `assets/sounds/`.

### Deleted

- `lib/data/session_repository.dart` (gate-2 Hive version)
- `lib/data/session_summary.dart`
- `lib/data/drill_log_repository.dart`
- `lib/data/drill_preset.dart`
- `lib/data/drill_preset.g.dart`
- `lib/data/hive_bootstrap.dart`
- `lib/data/in_memory_repositories.dart` (Hive-backed variants — the new fakes live in `test/test_helpers/`)
- `lib/data/preferences_repository.dart` (gate-2's Hive version — **moves to** `lib/services/preferences_repository.dart` as shared_preferences wrapper)
- `lib/models/drill_config.g.dart`
- `lib/models/target_group.g.dart`
- Any `*.g.dart` that Hive generated.

### Unchanged

- All tactical widgets (`lib/widgets/tactical/*.dart`).
- Plan-1 SQLite schema (`lib/db/schema.dart`, `lib/db/database_helper.dart`).
- `lib/repositories/shooter_repository.dart`.
- Firmware.

---

## Phase 2: Data Layer — Merge, Delete Hive, Build SQLite Replacements

Goal: by the end of Phase 2, `flutter test` passes with gate-2 data-layer tests **rewritten** and `flutter analyze` is clean. No UI work yet.

### Task 2.0: Set up a "safety-critical signatures" helper script

**Files:**
- Create: `tool/check_safety_critical.sh`

- [ ] **Step 1: Create the script**

```bash
cat > tool/check_safety_critical.sh <<'SCRIPT'
#!/usr/bin/env bash
# Verifies the 6 safety-critical signatures from commit e7f926b still exist.
# Run after any change that touches screens/program_*, drill_running_screen,
# services/ble_service, or state/app_state.

set -e
cd "$(git rev-parse --show-toplevel)"
fail=0
check() {
  local description=$1
  local pattern=$2
  local path=$3
  if ! grep -q -E "$pattern" "$path"; then
    echo "MISSING: $description  (pattern: $pattern in $path)"
    fail=1
  else
    echo "OK     : $description"
  fi
}

check "STOP-flood guard" \
  '_phase != DrillPhase\.running && _phase != DrillPhase\.arming' \
  lib/state/app_state.dart

check "BLE UUID str128 service" \
  'service\.uuid\.str128\.toLowerCase\(\)' \
  lib/services/ble_service.dart

check "BLE UUID str128 characteristic" \
  'char\.uuid\.str128\.toLowerCase\(\)' \
  lib/services/ble_service.dart

check "Program A nav listener detach" \
  'removeListener\(_onPhaseChanged\)' \
  lib/screens/program_a_setup_screen.dart

check "Program B nav listener detach" \
  'removeListener\(_onPhaseChanged\)' \
  lib/screens/program_b_setup_screen.dart

check "Drill-running nav listener detach" \
  'removeListener\(_checkDrillComplete\)' \
  lib/screens/drill_running_screen.dart

check "8s scan timeout" \
  'Timer\(const Duration\(seconds: 8\)' \
  lib/state/app_state.dart

check "SNAP/ send on reconnect" \
  'encodeSnap\(\)' \
  lib/state/app_state.dart

check "800ms STOP hold" \
  'Duration\(milliseconds: 800\)' \
  lib/screens/drill_running_screen.dart

check "PopScope canPop:false on drill screen" \
  'PopScope\(canPop: false' \
  lib/screens/drill_running_screen.dart

check "Program B scan entry (discoverTargets call)" \
  'state\.discoverTargets\(\)' \
  lib/screens/program_b_setup_screen.dart

if [ $fail -eq 1 ]; then
  echo
  echo "FAIL: one or more safety-critical signatures missing. Re-port from e7f926b."
  exit 1
fi

echo
echo "All 11 signatures present."
SCRIPT
chmod +x tool/check_safety_critical.sh
```

- [ ] **Step 2: Run it to confirm baseline passes**

Run: `./tool/check_safety_critical.sh`
Expected: `All 11 signatures present.`

- [ ] **Step 3: Commit**

```bash
git add tool/check_safety_critical.sh
git commit -m "chore(stage-3): add safety-critical signature check script"
```

---

### Task 2.1: Merge gate-2-work, deferring all conflicts

**Purpose:** Bring the 10 gate-2 commits into history so subsequent tasks can simply edit files rather than `git show` from another branch.

**Files:**
- Modify: lots, via `git merge`.

- [ ] **Step 1: Start the merge with `--no-commit` so we can reshape the tree before sealing**

Run:
```bash
git merge gate-2-work --no-commit --no-ff
```

Expected: conflicts reported in several files (`app_state.dart`, `main.dart`, `home_screen.dart`, program_*_setup_screen.dart, results_screen.dart, drill_running_screen.dart, pubspec.yaml, models, etc.). Index will contain BOTH sides marked.

- [ ] **Step 2: Accept gate-2's side for all non-conflicting new files (onboarding, preset_store, target_name_resolver, audio_service, tts_port, etc.)**

These should already be staged as additions from gate-2 with no conflict. Verify:

```bash
git status | grep 'new file:'
```

Expected: lists `lib/screens/onboarding/*`, `lib/widgets/drill_share_sheet.dart`, `lib/widgets/preset_row.dart`, `lib/widgets/target_actions_sheet.dart`, `lib/widgets/drill_result_image.dart`, `lib/util/preset_store.dart`, `lib/util/target_name_resolver.dart`, `lib/util/drill_log_codec.dart`, `lib/util/widget_to_image.dart`, `lib/util/results_view_model.dart`, `lib/services/audio_service.dart`, `assets/sounds/ready.mp3`, `assets/logo.png`.

- [ ] **Step 3: For every CONFLICTED file, checkout the `feature/system-v2` (OURS) version as the starting point — we'll re-introduce gate-2 features deliberately rather than reconciling 3-way diffs line-by-line**

```bash
# List conflicts
git diff --name-only --diff-filter=U
# For each conflicted file, take OURS (system-v2 tactical/SQLite):
for f in $(git diff --name-only --diff-filter=U); do
  git checkout --ours "$f"
  git add "$f"
done
```

Verify no more unmerged paths:
```bash
git diff --name-only --diff-filter=U
```
Expected: empty.

- [ ] **Step 4: Immediately delete the gate-2 data-layer files (they'll be replaced with SQLite versions in later tasks)**

```bash
git rm \
  lib/data/session_repository.dart \
  lib/data/session_summary.dart \
  lib/data/drill_log_repository.dart \
  lib/data/drill_preset.dart \
  lib/data/drill_preset.g.dart \
  lib/data/hive_bootstrap.dart \
  lib/data/in_memory_repositories.dart \
  lib/data/preferences_repository.dart \
  lib/models/drill_config.g.dart \
  lib/models/target_group.g.dart
# lib/data/ may now be empty — remove if so:
rmdir lib/data 2>/dev/null || true
```

- [ ] **Step 5: Run `git status` and inspect — the tree now has gate-2's new-file contributions plus plan-1's lib/ intact. Working tree is "partially gate-2".**

Run: `git status --short | head -40`

Expected: long list of `A  lib/screens/onboarding/...`, `A  lib/widgets/preset_row.dart`, `A  lib/services/audio_service.dart`, etc. plus our deletions.

- [ ] **Step 6: Build will fail because many new gate-2 files import Hive/DrillPreset/DrillLogRepository that we just deleted. That's expected — we fix it in 2.2–2.14. For now, commit the merge skeleton so we have a checkpoint.**

Run:
```bash
git commit -m "merge: gate-2-work → feature/stage-3-integration (data layer deferred)

Takes OURS for all conflicts (tactical + SQLite stack preserved). Accepts
gate-2 new files (onboarding, preset widgets, audio/tts services, drill
share sheet). Deletes gate-2 Hive data layer outright per locked gates
(see docs/superpowers/plans/2026-04-21-stage-3-gate2-integration.md).

Subsequent commits rebuild the data layer on SQLite + shared_preferences
and fix the compile errors gate-2 imports will now produce."
```

- [ ] **Step 7: Verify the commit recorded a merge (two parents)**

Run: `git log --oneline --graph -5`
Expected: top commit has a merge arrow, parents `99d04a1` and `8331ece`.

- [ ] **Step 8: Confirm `flutter pub get` still resolves — pubspec is still ours, no hive upgrade yet**

Run: `flutter pub get 2>&1 | tail -3`
Expected: `Got dependencies!` (no errors).

---

### Task 2.2: Drop Hive deps + add flutter_tts/just_audio/audio_session to pubspec

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Edit pubspec.yaml dependencies block**

Replace the `dependencies:` block contents with:

```yaml
dependencies:
  flutter:
    sdk: flutter
  crypto: ^3.0.3
  flutter_blue_plus: ^1.32.0
  flutter_tts: ^3.8.5
  google_fonts: ^6.2.1
  intl: ^0.19.0
  just_audio: ^0.9.44
  audio_session: ^0.1.25
  path_provider: ^2.1.0
  provider: ^6.1.0
  share_plus: ^9.0.0
  shared_preferences: ^2.2.0
  sqflite: ^2.3.0
  syncfusion_flutter_xlsio: ^25.1.0
  uuid: ^4.2.0
```

(No `hive`, no `hive_flutter`, no `screen_brightness`.)

- [ ] **Step 2: Replace `dev_dependencies:` block**

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  fake_async: ^1.3.0
  sqflite_common_ffi: ^2.3.0
```

(No `hive_generator`, no `build_runner` — we're not using either now.)

- [ ] **Step 3: Update the `flutter:` section to register the sounds asset**

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/
    - assets/sounds/
```

- [ ] **Step 4: Run `flutter pub get`**

Run: `flutter pub get 2>&1 | tail -3`
Expected: `Got dependencies!` with new packages (`flutter_tts`, `just_audio`, `audio_session`, `fake_async`) fetched.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(pubspec): drop Hive, add flutter_tts + audio deps

Hive goes away per Stage-3 gate decision — all domain data lives in
SQLite via plan-1's schema, UI settings in shared_preferences.
screen_brightness removed (outdoor-rule deferred with light theme).
fake_async added for ticker-based tests."
```

---

### Task 2.3: Strip Hive bindings from DrillConfig and TargetGroup models

The merge brought in gate-2's Hive-annotated versions of these files. We keep the class shapes but remove all `@HiveType`/`@HiveField` annotations + imports.

**Files:**
- Modify: `lib/models/drill_config.dart`
- Modify: `lib/models/target_group.dart`

- [ ] **Step 1: Inspect the gate-2 versions now on disk**

Run: `head -30 lib/models/drill_config.dart lib/models/target_group.dart`

Confirm you see `part '*.g.dart';` and `@HiveType(...)` decorations. These must go.

- [ ] **Step 2: Rewrite `lib/models/drill_config.dart` to the plan-1 shape (no Hive)**

Replace the entire file with:

```dart
import 'target_group.dart';

enum ProgramType { programA, programB }

class DrillConfig {
  ProgramType programType;
  double startMin;
  double startMax;
  double delayMin;
  double delayMax;
  int hitsMin;
  int hitsMax;
  List<TargetGroup> groups;
  List<int> targetIds;
  List<int> noShootIds;
  int iterations;

  DrillConfig({
    required this.programType,
    this.startMin = 1.0,
    this.startMax = 3.0,
    this.delayMin = 0.5,
    this.delayMax = 2.0,
    this.hitsMin = 1,
    this.hitsMax = 3,
    List<TargetGroup>? groups,
    List<int>? targetIds,
    List<int>? noShootIds,
    this.iterations = 5,
  })  : groups = groups ?? [],
        targetIds = targetIds ?? [],
        noShootIds = noShootIds ?? [];

  Map<String, Object?> toMap() => {
        'programType': programType == ProgramType.programA ? 'A' : 'B',
        'startMin': startMin,
        'startMax': startMax,
        'delayMin': delayMin,
        'delayMax': delayMax,
        'hitsMin': hitsMin,
        'hitsMax': hitsMax,
        'groups': groups.map((g) => g.toMap()).toList(),
        'targetIds': [...targetIds],
        'noShootIds': [...noShootIds],
        'iterations': iterations,
      };

  factory DrillConfig.fromMap(Map<String, Object?> m) => DrillConfig(
        programType: (m['programType'] as String) == 'A'
            ? ProgramType.programA
            : ProgramType.programB,
        startMin: (m['startMin'] as num).toDouble(),
        startMax: (m['startMax'] as num).toDouble(),
        delayMin: (m['delayMin'] as num).toDouble(),
        delayMax: (m['delayMax'] as num).toDouble(),
        hitsMin: m['hitsMin'] as int,
        hitsMax: m['hitsMax'] as int,
        groups: (m['groups'] as List)
            .map((g) => TargetGroup.fromMap(g as Map<String, Object?>))
            .toList(),
        targetIds: (m['targetIds'] as List).cast<int>(),
        noShootIds: (m['noShootIds'] as List).cast<int>(),
        iterations: m['iterations'] as int,
      );
}
```

- [ ] **Step 3: Rewrite `lib/models/target_group.dart` to a Hive-free shape**

Replace the entire file with:

```dart
class TargetGroup {
  List<int> targetIds;

  TargetGroup({List<int>? targetIds}) : targetIds = targetIds ?? [];

  Map<String, Object?> toMap() => {
        'targetIds': [...targetIds],
      };

  factory TargetGroup.fromMap(Map<String, Object?> m) =>
      TargetGroup(targetIds: (m['targetIds'] as List).cast<int>());
}
```

- [ ] **Step 4: Verify no more Hive imports in models/**

Run: `grep -rn 'hive' lib/models/ 2>/dev/null`
Expected: empty.

- [ ] **Step 5: Verify analyze doesn't regress further than the known gate-2 import errors**

Run: `flutter analyze lib/models/ 2>&1 | tail -10`
Expected: 0 issues in `lib/models/`.

- [ ] **Step 6: Commit**

```bash
git add lib/models/drill_config.dart lib/models/target_group.dart
git commit -m "refactor(models): strip Hive annotations from DrillConfig + TargetGroup

toMap/fromMap provided explicitly for SQLite + canonical-JSON hashing.
Matches plan-1 shape; Hive-generated *.g.dart files already deleted in
the merge commit."
```

---

### Task 2.4: Add `getEventsFor(sessionId)` to plan-1 SessionRepository

New read-only method so drill_share_sheet / drill_result_image / drill_log_codec can render event streams from the SQLite truth instead of gate-2's deleted DrillLogRepository.

**Files:**
- Modify: `lib/repositories/session_repository.dart`
- Test: `test/repositories/session_repository_events_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/repositories/session_repository_events_test.dart`:

```dart
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/models/session_record.dart';
import 'package:atriarch/repositories/session_repository.dart';
import 'package:atriarch/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SessionRepository.getEventsFor', () {
    test('returns events in sequence order', () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = SessionRepository(db);
      await repo.insert(SessionRecord(
        id: 's1',
        shooterId: kUnassignedShooterId,
        programType: 'A',
        configJson: '{}',
        configHash: 'hash',
        startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        finishedNormally: false,
        iterationsCompleted: 0,
      ));
      await repo.appendEvents('s1', [
        SessionEvent(
          type: EventType.targetActivated,
          targetId: 1,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1100),
        ),
        SessionEvent(
          type: EventType.hitDetected,
          targetId: 1,
          hitNumber: 1,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1200),
        ),
        SessionEvent(
          type: EventType.drillFinished,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1300),
        ),
      ]);

      final events = await repo.getEventsFor('s1');
      expect(events, hasLength(3));
      expect(events[0].type, EventType.targetActivated);
      expect(events[1].type, EventType.hitDetected);
      expect(events[2].type, EventType.drillFinished);
      await db.close();
    });

    test('returns empty list for unknown session id', () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = SessionRepository(db);
      expect(await repo.getEventsFor('nope'), isEmpty);
      await db.close();
    });
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `flutter test test/repositories/session_repository_events_test.dart`
Expected: FAIL — `getEventsFor` not defined.

- [ ] **Step 3: Implement `getEventsFor` in `lib/repositories/session_repository.dart`**

Add this method after `lastEventTimestamp` (around line 92):

```dart
  /// Returns every event for a session, ordered by sequence.
  Future<List<SessionEvent>> getEventsFor(String sessionId) async {
    final rows = await _db.query(
      'session_events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'sequence ASC',
    );
    return rows.map(_rowToEvent).toList();
  }

  static SessionEvent _rowToEvent(Map<String, Object?> row) => SessionEvent(
        type: _codeToType(row['type'] as String),
        targetId: row['target_id'] as int?,
        hitNumber: row['hit_number'] as int?,
        requiredHits: row['required_hits'] as int?,
        totalTimeMs: row['total_time_ms'] as int?,
        errorDetail: row['error_detail'] as String?,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
      );

  static EventType _codeToType(String code) {
    switch (code) {
      case 'ACT':
        return EventType.targetActivated;
      case 'HIT':
        return EventType.hitDetected;
      case 'DONE':
        return EventType.targetComplete;
      case 'NS':
        return EventType.noShootViolation;
      case 'LATE':
        return EventType.lateHit;
      case 'FIN':
        return EventType.drillFinished;
      case 'ERROR':
      default:
        return EventType.error;
    }
  }
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/repositories/session_repository_events_test.dart`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/session_repository.dart test/repositories/session_repository_events_test.dart
git commit -m "feat(session_repo): add getEventsFor read-only method

Replaces the read side of gate-2's deleted DrillLogRepository.
drill_share_sheet + drill_result_image will drive their rendering from
this instead of a separate log blob."
```

---

### Task 2.5: Create the `DrillTemplate` model (TDD)

**Files:**
- Create: `lib/models/drill_template.dart`
- Test: `test/models/drill_template_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/drill_template.dart';
import 'package:atriarch/services/config_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DrillTemplate', () {
    test('toRow serializes fields into drill_templates row shape', () {
      final config = DrillConfig(programType: ProgramType.programA);
      final t = DrillTemplate(
        id: 'tpl1',
        shooterId: null,
        name: 'Warm-up',
        programType: ProgramType.programA,
        config: config,
        configHash: ConfigHasher.hash(config),
        createdAt: DateTime.fromMillisecondsSinceEpoch(1234),
      );
      final row = t.toRow();
      expect(row['id'], 'tpl1');
      expect(row['shooter_id'], isNull);
      expect(row['name'], 'Warm-up');
      expect(row['program_type'], 'A');
      expect(row['config_json'], ConfigHasher.canonicalJson(config));
      expect(row['config_hash'], ConfigHasher.hash(config));
      expect(row['created_at'], 1234);
    });

    test('fromRow round-trips through toRow', () {
      final config = DrillConfig(programType: ProgramType.programB);
      final original = DrillTemplate(
        id: 'tpl2',
        shooterId: 'shooter-x',
        name: 'Mover',
        programType: ProgramType.programB,
        config: config,
        configHash: ConfigHasher.hash(config),
        createdAt: DateTime.fromMillisecondsSinceEpoch(5678),
      );
      final round = DrillTemplate.fromRow(original.toRow());
      expect(round.id, original.id);
      expect(round.shooterId, original.shooterId);
      expect(round.name, original.name);
      expect(round.programType, original.programType);
      expect(round.configHash, original.configHash);
      expect(round.createdAt, original.createdAt);
      expect(round.config.programType, original.config.programType);
    });
  });
}
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `flutter test test/models/drill_template_test.dart`
Expected: FAIL — `DrillTemplate` undefined.

- [ ] **Step 3: Create `lib/models/drill_template.dart`**

```dart
import 'dart:convert';

import '../services/config_hasher.dart';
import 'drill_config.dart';

/// A saved drill configuration. Maps 1:1 to a row in the `drill_templates`
/// SQLite table. User-facing label is "preset"; the code-level name is
/// DrillTemplate to match the schema.
///
/// `shooterId == null` means an app-wide preset (gate-2's default). The
/// Instructor SKU can later introduce per-shooter presets without a schema
/// migration.
class DrillTemplate {
  final String id;
  final String? shooterId;
  final String name;
  final ProgramType programType;
  final DrillConfig config;
  final String configHash;
  final DateTime createdAt;

  const DrillTemplate({
    required this.id,
    required this.shooterId,
    required this.name,
    required this.programType,
    required this.config,
    required this.configHash,
    required this.createdAt,
  });

  String get programTypeCode => programType == ProgramType.programA ? 'A' : 'B';

  Map<String, Object?> toRow() => {
        'id': id,
        'shooter_id': shooterId,
        'name': name,
        'program_type': programTypeCode,
        'config_json': ConfigHasher.canonicalJson(config),
        'config_hash': configHash,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory DrillTemplate.fromRow(Map<String, Object?> row) {
    final configJson = row['config_json'] as String;
    final configMap = json.decode(configJson) as Map<String, Object?>;
    return DrillTemplate(
      id: row['id'] as String,
      shooterId: row['shooter_id'] as String?,
      name: row['name'] as String,
      programType: (row['program_type'] as String) == 'A'
          ? ProgramType.programA
          : ProgramType.programB,
      config: DrillConfig.fromMap(configMap),
      configHash: row['config_hash'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }
}
```

- [ ] **Step 4: Run test to confirm pass**

Run: `flutter test test/models/drill_template_test.dart`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/models/drill_template.dart test/models/drill_template_test.dart
git commit -m "feat(models): add DrillTemplate domain class backed by drill_templates

Replaces gate-2's Hive DrillPreset. Maps 1:1 to plan-1's SQLite schema.
shooter_id nullable so gate-2's app-wide preset flow works unchanged;
Instructor SKU can add per-shooter presets later without migration."
```

---

### Task 2.6: Create `DrillTemplateRepository` (TDD)

**Files:**
- Create: `lib/repositories/drill_template_repository.dart`
- Test: `test/repositories/drill_template_repository_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/drill_template.dart';
import 'package:atriarch/repositories/drill_template_repository.dart';
import 'package:atriarch/services/config_hasher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DrillTemplate _tpl(String id, String name, {String? shooterId, int createdMs = 0}) {
  final config = DrillConfig(programType: ProgramType.programA);
  return DrillTemplate(
    id: id,
    shooterId: shooterId,
    name: name,
    programType: ProgramType.programA,
    config: config,
    configHash: ConfigHasher.hash(config),
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DrillTemplateRepository', () {
    test('insert then getById returns the template', () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = DrillTemplateRepository(db);
      final t = _tpl('a', 'Warm-up');
      await repo.insert(t);
      final got = await repo.getById('a');
      expect(got, isNotNull);
      expect(got!.name, 'Warm-up');
      expect(got.configHash, t.configHash);
      await db.close();
    });

    test('listAll returns templates sorted by name case-insensitive', () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = DrillTemplateRepository(db);
      await repo.insert(_tpl('a', 'zebra'));
      await repo.insert(_tpl('b', 'Apple'));
      await repo.insert(_tpl('c', 'mango'));
      final all = await repo.listAll();
      expect(all.map((t) => t.name).toList(), ['Apple', 'mango', 'zebra']);
      await db.close();
    });

    test('upsert replaces an existing template with the same id', () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = DrillTemplateRepository(db);
      await repo.upsert(_tpl('a', 'v1'));
      await repo.upsert(_tpl('a', 'v2'));
      expect((await repo.getById('a'))!.name, 'v2');
      expect((await repo.listAll()).length, 1);
      await db.close();
    });

    test('delete removes the row', () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = DrillTemplateRepository(db);
      await repo.insert(_tpl('a', 'X'));
      await repo.delete('a');
      expect(await repo.getById('a'), isNull);
      await db.close();
    });
  });
}
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `flutter test test/repositories/drill_template_repository_test.dart`
Expected: FAIL — `DrillTemplateRepository` undefined.

- [ ] **Step 3: Create `lib/repositories/drill_template_repository.dart`**

```dart
import 'package:sqflite/sqflite.dart';

import '../models/drill_template.dart';

/// CRUD over the `drill_templates` SQLite table.
///
/// User-facing label is "preset"; the code-level name is DrillTemplate to
/// match the schema. App-wide templates have shooter_id NULL.
class DrillTemplateRepository {
  final Database _db;
  DrillTemplateRepository(this._db);

  Future<void> insert(DrillTemplate t) async {
    await _db.insert(
      'drill_templates',
      t.toRow(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Insert or replace — used by the "Save preset" flow which reuses an id
  /// on re-save.
  Future<void> upsert(DrillTemplate t) async {
    await _db.insert(
      'drill_templates',
      t.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DrillTemplate?> getById(String id) async {
    final rows = await _db.query(
      'drill_templates',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DrillTemplate.fromRow(rows.first);
  }

  /// All templates sorted alphabetically by name (case-insensitive). Matches
  /// gate-2's dropdown ordering.
  Future<List<DrillTemplate>> listAll() async {
    final rows = await _db.query(
      'drill_templates',
      orderBy: 'LOWER(name) ASC',
    );
    return rows.map(DrillTemplate.fromRow).toList();
  }

  Future<void> delete(String id) async {
    await _db.delete(
      'drill_templates',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
```

- [ ] **Step 4: Run test to confirm it passes**

Run: `flutter test test/repositories/drill_template_repository_test.dart`
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/drill_template_repository.dart test/repositories/drill_template_repository_test.dart
git commit -m "feat(repo): DrillTemplateRepository — SQLite CRUD over drill_templates

Case-insensitive alpha sort for listAll matches gate-2's preset dropdown
ordering. upsert used by 'Save preset' flow that reuses an id on re-save."
```

---

### Task 2.7: Create thin `PreferencesRepository` (shared_preferences wrapper)

Replaces gate-2's Hive `PreferencesRepository` minus the preset CRUD (that's in DrillTemplateRepository now). Keeps only UI settings, target names, removed-target ids, and default-preset-id.

**Files:**
- Create: `lib/services/preferences_repository.dart`
- Test: `test/services/preferences_repository_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:atriarch/services/preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PreferencesRepository', () {
    test('default preset id round-trips', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = PreferencesRepository(prefs);
      expect(await repo.getDefaultPresetId(), isNull);
      await repo.setDefaultPresetId('tpl-1');
      expect(await repo.getDefaultPresetId(), 'tpl-1');
      await repo.setDefaultPresetId(null);
      expect(await repo.getDefaultPresetId(), isNull);
    });

    test('target names round-trip', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = PreferencesRepository(prefs);
      expect(await repo.getTargetNames(), isEmpty);
      await repo.setTargetName(1, 'Alpha');
      await repo.setTargetName(2, 'Bravo');
      expect(await repo.getTargetNames(), {1: 'Alpha', 2: 'Bravo'});
      await repo.setTargetName(1, null); // remove
      expect(await repo.getTargetNames(), {2: 'Bravo'});
    });

    test('removed target ids round-trip', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = PreferencesRepository(prefs);
      expect(await repo.getRemovedTargetIds(), isEmpty);
      await repo.setRemovedTargetIds({3, 7, 1});
      expect(await repo.getRemovedTargetIds(), {1, 3, 7});
    });

    test('onboarding complete flag', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = PreferencesRepository(prefs);
      expect(await repo.isOnboardingComplete(), isFalse);
      await repo.setOnboardingComplete(true);
      expect(await repo.isOnboardingComplete(), isTrue);
    });

    test('range activity timestamp', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = PreferencesRepository(prefs);
      expect(await repo.getLastRangeActivity(), isNull);
      final t = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
      await repo.setLastRangeActivity(t);
      expect(await repo.getLastRangeActivity(), t);
    });
  });
}
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `flutter test test/services/preferences_repository_test.dart`
Expected: FAIL — `PreferencesRepository` undefined.

- [ ] **Step 3: Create `lib/services/preferences_repository.dart`**

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper over shared_preferences for UI-adjacent settings.
/// Domain data (shooters, sessions, templates) lives in SQLite.
class PreferencesRepository {
  static const String _kDefaultPresetId = 'default_preset_id';
  static const String _kTargetNames = 'target_names';
  static const String _kRemovedTargetIds = 'removed_target_ids';
  static const String _kOnboardingComplete = 'onboarding_complete';
  static const String _kLastRangeActivity = 'last_range_activity_ms';

  final SharedPreferences _prefs;
  PreferencesRepository(this._prefs);

  // --- default preset id ---
  Future<String?> getDefaultPresetId() async =>
      _prefs.getString(_kDefaultPresetId);

  Future<void> setDefaultPresetId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kDefaultPresetId);
    } else {
      await _prefs.setString(_kDefaultPresetId, id);
    }
  }

  // --- target names (Map<int,String>) ---
  Future<Map<int, String>> getTargetNames() async {
    final raw = _prefs.getString(_kTargetNames);
    if (raw == null || raw.isEmpty) return <int, String>{};
    final decoded = json.decode(raw);
    if (decoded is! Map) return <int, String>{};
    return decoded.map<int, String>((k, v) {
      final id = k is int ? k : int.tryParse('$k') ?? -1;
      return MapEntry(id, '$v');
    })..removeWhere((k, _) => k < 0);
  }

  Future<void> setTargetName(int targetId, String? displayName) async {
    final current = Map<String, String>.from(
      (json.decode(_prefs.getString(_kTargetNames) ?? '{}') as Map)
          .map((k, v) => MapEntry('$k', '$v')),
    );
    final key = targetId.toString();
    if (displayName == null || displayName.isEmpty) {
      current.remove(key);
    } else {
      current[key] = displayName;
    }
    if (current.isEmpty) {
      await _prefs.remove(_kTargetNames);
    } else {
      await _prefs.setString(_kTargetNames, json.encode(current));
    }
  }

  // --- removed target ids (Set<int>) ---
  Future<Set<int>> getRemovedTargetIds() async {
    final raw = _prefs.getString(_kRemovedTargetIds);
    if (raw == null || raw.isEmpty) return <int>{};
    return raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
  }

  Future<void> setRemovedTargetIds(Set<int> ids) async {
    if (ids.isEmpty) {
      await _prefs.remove(_kRemovedTargetIds);
    } else {
      final sorted = ids.toList()..sort();
      await _prefs.setString(_kRemovedTargetIds, sorted.join(','));
    }
  }

  // --- onboarding flag ---
  Future<bool> isOnboardingComplete() async =>
      _prefs.getBool(_kOnboardingComplete) ?? false;

  Future<void> setOnboardingComplete(bool v) async =>
      _prefs.setBool(_kOnboardingComplete, v);

  // --- range-session activity timestamp ---
  /// Stamped on drill start and end. RangeSessionView uses this to compute
  /// the visible-drills cutoff (>=8h gap resets the view).
  Future<DateTime?> getLastRangeActivity() async {
    final ms = _prefs.getInt(_kLastRangeActivity);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastRangeActivity(DateTime t) async =>
      _prefs.setInt(_kLastRangeActivity, t.millisecondsSinceEpoch);

  Future<void> clearLastRangeActivity() async =>
      _prefs.remove(_kLastRangeActivity);
}
```

- [ ] **Step 4: Run test to confirm it passes**

Run: `flutter test test/services/preferences_repository_test.dart`
Expected: PASS — 5 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/preferences_repository.dart test/services/preferences_repository_test.dart
git commit -m "feat(prefs): shared_preferences PreferencesRepository

Replaces gate-2's Hive version (which was deleted in merge skeleton).
Keeps default preset id, target names, removed target ids, onboarding
flag, and last-range-activity timestamp. Preset CRUD moved to
DrillTemplateRepository. Schema mirrors gate-2's keys so an app-upgrade
can optionally migrate — though Stage-3 ships assuming a clean install."
```

---

### Task 2.8: Create `RangeSessionView` service (TDD)

Derived view over plan-1's `sessions` table with 8h cutoff driven by `last_range_activity_ms` in shared_preferences.

**Files:**
- Create: `lib/services/range_session_view.dart`
- Test: `test/services/range_session_view_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:atriarch/constants.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/session_record.dart';
import 'package:atriarch/repositories/session_repository.dart';
import 'package:atriarch/services/preferences_repository.dart';
import 'package:atriarch/services/range_session_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

SessionRecord _rec(String id, int startedMs, {int? endedMs, bool finished = true}) =>
    SessionRecord(
      id: id,
      shooterId: kUnassignedShooterId,
      programType: 'A',
      configJson: '{}',
      configHash: 'h',
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedMs),
      endedAt: endedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(endedMs),
      finishedNormally: finished,
      iterationsCompleted: 0,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RangeSessionView', () {
    test('returns empty list when no sessions exist', () async {
      final db = await DatabaseHelper.openForTesting();
      final prefs = await SharedPreferences.getInstance();
      final view = RangeSessionView(
        sessions: SessionRepository(db),
        preferences: PreferencesRepository(prefs),
        clock: () => DateTime.fromMillisecondsSinceEpoch(1_000_000),
      );
      expect(await view.listCurrent(), isEmpty);
      await db.close();
    });

    test('returns all sessions since the cutoff when gap < 8h', () async {
      final db = await DatabaseHelper.openForTesting();
      final sessions = SessionRepository(db);
      final prefs = await SharedPreferences.getInstance();
      final preferences = PreferencesRepository(prefs);

      // Stamp last activity 2h ago (the view cutoff).
      final now = DateTime.fromMillisecondsSinceEpoch(1_000_000_000_000);
      final twoHoursAgo = now.subtract(const Duration(hours: 2));
      await preferences.setLastRangeActivity(twoHoursAgo);

      await sessions.insert(_rec('s1', twoHoursAgo.millisecondsSinceEpoch + 1));
      await sessions.insert(_rec('s2', now.millisecondsSinceEpoch - 60_000));
      await sessions.insert(_rec(
        'old',
        twoHoursAgo.millisecondsSinceEpoch - 1,
      ));

      final view = RangeSessionView(
        sessions: sessions,
        preferences: preferences,
        clock: () => now,
      );
      final got = await view.listCurrent();
      expect(got.map((s) => s.id).toList(), ['s2', 's1']);
      await db.close();
    });

    test('resets cutoff to now when last activity was >= 8h ago', () async {
      final db = await DatabaseHelper.openForTesting();
      final sessions = SessionRepository(db);
      final prefs = await SharedPreferences.getInstance();
      final preferences = PreferencesRepository(prefs);

      final now = DateTime.fromMillisecondsSinceEpoch(1_000_000_000_000);
      final nineHoursAgo = now.subtract(const Duration(hours: 9));
      await preferences.setLastRangeActivity(nineHoursAgo);

      await sessions.insert(_rec('old', nineHoursAgo.millisecondsSinceEpoch + 1));

      final view = RangeSessionView(
        sessions: sessions,
        preferences: preferences,
        clock: () => now,
      );
      expect(await view.listCurrent(), isEmpty);
      await db.close();
    });

    test('markActivity stamps now and is read back by listCurrent', () async {
      final db = await DatabaseHelper.openForTesting();
      final sessions = SessionRepository(db);
      final prefs = await SharedPreferences.getInstance();
      final preferences = PreferencesRepository(prefs);

      final now = DateTime.fromMillisecondsSinceEpoch(1_000_000_000_000);
      final view = RangeSessionView(
        sessions: sessions,
        preferences: preferences,
        clock: () => now,
      );
      await view.markActivity();
      expect(await preferences.getLastRangeActivity(), now);
      await db.close();
    });

    test('clearCurrent sets cutoff to now without deleting rows', () async {
      final db = await DatabaseHelper.openForTesting();
      final sessions = SessionRepository(db);
      final prefs = await SharedPreferences.getInstance();
      final preferences = PreferencesRepository(prefs);

      final now = DateTime.fromMillisecondsSinceEpoch(1_000_000_000_000);
      final halfHourAgo = now.subtract(const Duration(minutes: 30));
      await preferences.setLastRangeActivity(halfHourAgo);
      await sessions.insert(_rec('s1', halfHourAgo.millisecondsSinceEpoch + 1));

      final view = RangeSessionView(
        sessions: sessions,
        preferences: preferences,
        clock: () => now,
      );
      // Before clear: session is visible.
      expect((await view.listCurrent()).map((s) => s.id), ['s1']);

      await view.clearCurrent();
      // After clear: visible list is empty; row still exists.
      expect(await view.listCurrent(), isEmpty);
      expect(await sessions.getById('s1'), isNotNull);
      await db.close();
    });
  });
}
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `flutter test test/services/range_session_view_test.dart`
Expected: FAIL — `RangeSessionView` undefined.

- [ ] **Step 3: Create `lib/services/range_session_view.dart`**

```dart
import 'package:sqflite/sqflite.dart';

import '../models/session_record.dart';
import '../repositories/session_repository.dart';
import 'preferences_repository.dart';

/// Derived "current range session" view.
///
/// A range session = the drills the shooter has run during their current
/// range visit. Bounded by the 8h inactivity rule: if the last stamped
/// activity was >=8h ago, the cutoff is "now" (nothing visible).
/// Otherwise the cutoff is the last-activity timestamp.
///
/// No new storage: [listCurrent] is a query against plan-1's `sessions`
/// table, and [clearCurrent] just re-stamps the cutoff.
class RangeSessionView {
  static const Duration _gap = Duration(hours: 8);

  final SessionRepository sessions;
  final PreferencesRepository preferences;
  final DateTime Function() _clock;

  RangeSessionView({
    required this.sessions,
    required this.preferences,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The effective cutoff for the visible list. If no last-activity stamp
  /// exists or the gap exceeds [_gap], the cutoff is now.
  Future<DateTime> currentCutoff() async {
    final last = await preferences.getLastRangeActivity();
    final now = _clock();
    if (last == null) return now;
    if (now.difference(last) >= _gap) return now;
    return last;
  }

  /// Sessions started at or after the current cutoff, most recent first.
  Future<List<SessionRecord>> listCurrent() async {
    final cutoff = await currentCutoff();
    final db = _dbFor(sessions);
    final rows = await db.query(
      'sessions',
      where: 'started_at >= ?',
      whereArgs: [cutoff.millisecondsSinceEpoch],
      orderBy: 'started_at DESC',
    );
    return rows.map(SessionRecord.fromMap).toList();
  }

  /// Stamp current time as "activity". Call on drill start AND end.
  Future<void> markActivity() async =>
      preferences.setLastRangeActivity(_clock());

  /// "Clear this range session" → set the cutoff to now. Nothing is deleted.
  Future<void> clearCurrent() async =>
      preferences.setLastRangeActivity(_clock());

  // SessionRepository exposes its Database internally; reach in because
  // the view needs a cross-table query (sessions ORDER BY started_at) that
  // the repository's current API doesn't expose as a single call.
  // If this proves awkward in the future, promote the query into
  // SessionRepository.listStartedSince(DateTime).
  Database _dbFor(SessionRepository repo) {
    // ignore: invalid_use_of_visible_for_testing_member
    return repo.rawDbForRangeView;
  }
}
```

- [ ] **Step 4: Expose the raw DB on `SessionRepository` for the view to use**

Modify `lib/repositories/session_repository.dart`. Add at the top of the class (after the existing `_db` field, around line 8):

```dart
  /// Escape hatch for services that need cross-table queries (e.g.
  /// RangeSessionView). Do NOT use for CRUD that could live on a repository.
  @visibleForTesting
  Database get rawDbForRangeView => _db;
```

And add the import if missing:

```dart
import 'package:flutter/foundation.dart';
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `flutter test test/services/range_session_view_test.dart`
Expected: PASS — 5 tests.

- [ ] **Step 6: Commit**

```bash
git add lib/services/range_session_view.dart test/services/range_session_view_test.dart lib/repositories/session_repository.dart
git commit -m "feat(range): RangeSessionView — derived view, no new storage

Replaces gate-2's SessionRepository (deleted). Cutoff lives in
shared_preferences as last_range_activity_ms; >=8h gap resets it.
listCurrent is a sessions-table query. clearCurrent re-stamps cutoff
rather than deleting rows."
```

---

### Task 2.9: Port `AudioService` from gate-2 (minor cleanup)

Gate-2's `AudioService` uses `just_audio` to play a "ready" chime. Port as-is, no semantic changes.

**Files:**
- Overwrite: `lib/services/audio_service.dart` (already present from merge — verify it's the gate-2 version)
- Test: `test/services/audio_service_test.dart`

- [ ] **Step 1: Confirm the merge brought in the file**

Run: `head -20 lib/services/audio_service.dart`
Expected: gate-2's class definition. If missing (shouldn't be, but sanity-check), copy from `.worktrees/gate-2/lib/services/audio_service.dart`.

- [ ] **Step 2: Read the file and list its public surface**

Run: `grep -n 'class\|Future\|void\|bool ' lib/services/audio_service.dart | head -20`

Note the public methods (likely `init`, `playReadyChime`, `dispose`).

- [ ] **Step 3: Write a minimal smoke test confirming a FakeAudioService can substitute**

(Fake is built in Phase 4 — for now we just verify the real class compiles.)

Create `test/services/audio_service_test.dart`:

```dart
import 'package:atriarch/services/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AudioService can be instantiated', () {
    final svc = AudioService();
    // Not calling init() — that touches platform channels.
    expect(svc, isNotNull);
  });
}
```

- [ ] **Step 4: Run test**

Run: `flutter test test/services/audio_service_test.dart`
Expected: PASS (just verifies compile + instantiate).

- [ ] **Step 5: Commit**

```bash
git add lib/services/audio_service.dart test/services/audio_service_test.dart
git commit -m "chore(audio): confirm AudioService ported from gate-2

just_audio-backed ready-chime. Smoke test only — deeper coverage lands
in Phase 4 via FakeAudioService pattern."
```

---

### Task 2.10: Port `TtsPort` + `TargetNameResolver` from gate-2

These are self-contained utilities with no Hive dependency. If the merge brought them in, they should compile as-is once their callers are updated.

**Files:**
- Verify present: `lib/util/target_name_resolver.dart`
- Create if missing: `lib/services/tts_port.dart`

- [ ] **Step 1: Check which files exist post-merge**

Run: `ls lib/services/tts_port.dart lib/util/target_name_resolver.dart 2>&1`

- [ ] **Step 2: If `tts_port.dart` is missing or lives at `lib/util/tts_port.dart`, copy from gate-2**

Gate-2 has it at `.worktrees/gate-2/lib/services/` (check) or embedded inline somewhere. Run:

```bash
find .worktrees/gate-2/lib -name 'tts_port.dart'
```

If found, copy it to `lib/services/tts_port.dart`:

```bash
cp .worktrees/gate-2/<found-path> lib/services/tts_port.dart
```

If not found as a separate file, gate-2 defined it inline in `app_state.dart` — extract it into `lib/services/tts_port.dart`:

```dart
/// Abstraction over `flutter_tts` for walk-the-range voice prompts. Extracted
/// so widget tests can substitute a RecordingTtsPort.
abstract class TtsPort {
  Future<void> speak(String text);
  Future<void> stop();
}

/// Production implementation using package:flutter_tts.
class FlutterTtsPort implements TtsPort {
  // Lazy import to avoid plugin init at top-level.
  final dynamic _tts;
  FlutterTtsPort._(this._tts);

  static Future<FlutterTtsPort> create() async {
    // ignore: avoid_dynamic_calls
    final tts = _newFlutterTts();
    return FlutterTtsPort._(tts);
  }

  @override
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}

// Separate function so the FlutterTts import is co-located with its use.
dynamic _newFlutterTts() {
  // ignore: implementation_imports
  // ignore: unused_import
  throw UnimplementedError(
    'Replace with `import "package:flutter_tts/flutter_tts.dart"; return FlutterTts();`',
  );
}
```

Then replace the body of `_newFlutterTts()` with the real import at the top of the file:

```dart
import 'package:flutter_tts/flutter_tts.dart';

// ... class defs above ...

FlutterTts _newFlutterTts() => FlutterTts();
```

And retype the field: `final FlutterTts _tts;` instead of `dynamic`.

- [ ] **Step 3: Run `flutter analyze lib/services/tts_port.dart lib/util/target_name_resolver.dart`**

Expected: 0 issues. Fix any lint warnings in place.

- [ ] **Step 4: Smoke test — TTS port can be constructed (not called)**

Create `test/services/tts_port_test.dart`:

```dart
import 'package:atriarch/services/tts_port.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingTts implements TtsPort {
  final List<String> spoken = [];
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
}

void main() {
  test('a TtsPort substitute records spoken text', () async {
    final tts = _RecordingTts();
    await tts.speak('target one');
    expect(tts.spoken, ['target one']);
  });
}
```

- [ ] **Step 5: Run the smoke test**

Run: `flutter test test/services/tts_port_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/tts_port.dart lib/util/target_name_resolver.dart test/services/tts_port_test.dart
git commit -m "chore(walk-range): port TtsPort + TargetNameResolver from gate-2

TtsPort abstracts flutter_tts so widget tests can substitute a
RecordingTtsPort. TargetNameResolver is already Hive-free."
```

---

### Task 2.11: Strip `ThemeController` down to dark-only

Per locked gate: `ThemePreference.light` and `ThemePreference.auto` removed. `screen_brightness` dep gone. Settings's theme radio removed (that's Phase 3 work).

**Files:**
- Modify: `lib/theme/theme_controller.dart` OR delete and wire `ThemeMode.dark` directly.
- Test: `test/theme/theme_controller_test.dart` (whatever gate-2 brought — rewrite)

- [ ] **Step 1: Decide: keep a stub ThemeController or delete?**

Keep a stub — it still has value as a `ChangeNotifier` hook for future dark-only-with-brightness-override work, and it lets `main.dart` bind `themeMode` without knowing the decision was "always dark." Delete the light/auto code paths.

- [ ] **Step 2: Replace `lib/theme/theme_controller.dart` with the dark-only version**

```dart
import 'package:flutter/material.dart';

/// Dark-only theme controller (Stage 3 gate decision).
///
/// Gate-2's `ThemePreference.light`/`auto` and the `screen_brightness`
/// outdoor-rule were stripped — see
/// `docs/superpowers/plans/2026-04-21-stage-3-gate2-integration.md`
/// and memory `project_theme_dark_only.md`.
///
/// Left as a ChangeNotifier so future dark-only-with-drill-brightness-
/// override work can reintroduce lifecycle hooks here without the
/// MaterialApp wiring changing. For now it's a constant: always
/// [ThemeMode.dark].
class ThemeController extends ChangeNotifier {
  ThemeMode get themeMode => ThemeMode.dark;
}
```

- [ ] **Step 3: Delete gate-2's `theme_controller_test.dart` if present**

```bash
rm -f test/theme/theme_controller_test.dart
```

(Gate-2 tested light/auto/brightness which no longer exist. A trivial dark-only controller needs no test.)

- [ ] **Step 4: Run analyze to catch any callers of the removed ThemePreference enum**

Run: `flutter analyze lib/ 2>&1 | grep -i 'theme' | head`

If callers exist (likely `settings_screen.dart` from gate-2), fix those in Phase 3. For now the build just needs to compile — add a placeholder comment at the caller site if necessary to track it in Phase 3.

- [ ] **Step 5: Commit**

```bash
git add lib/theme/theme_controller.dart test/theme/theme_controller_test.dart
git commit -m "refactor(theme): strip ThemeController to dark-only

Gate-2's ThemePreference.light/auto + screen_brightness outdoor-rule
removed per locked Stage-3 gate. Kept as a ChangeNotifier shim so
future brightness hooks land here without MaterialApp changes."
```

---

### Task 2.12: Rewire AppState to host gate-2 additions + plan-1 DI

This is the largest single change in Phase 2. Preserves EVERY plan-1 field and every safety-critical behaviour. Adds gate-2's preferences/audio/tts/onboarding/target-names state.

**Files:**
- Modify: `lib/state/app_state.dart`
- Test: `test/state/app_state_*_test.dart` (existing tests stay green)

- [ ] **Step 1: Read the gate-2 version of app_state.dart for reference**

Run: `wc -l .worktrees/gate-2/lib/state/app_state.dart`

Note the diff will be large but we only need to layer gate-2 FIELDS + LIFECYCLE HOOKS onto plan-1's existing app_state.

- [ ] **Step 2: Rewrite `lib/state/app_state.dart` keeping plan-1 skeleton intact**

Replace the file contents (starting from `lib/state/app_state.dart` current content — plan-1 shape) with the merged version below. The changes vs plan-1:
- Add imports for the new services.
- Add new private fields + constructor params.
- Add `preferences` / `audio` / `tts` / `rangeSessionView` / `drillTemplates` getters.
- Add `_readyChimePlayedForCurrentCycle`, `_discoveryDoneSeenForCurrentCycle`, `_onboardingComplete`, `_targetNames`, `_removedTargetIds`, `_showRemoved`.
- In `discoverTargets`: reset cycle flags.
- In `_handleIncomingData` on `DiscoveryDone`: play chime if first-time.
- In `startDrill`: call `rangeSessionView.markActivity()`.
- In `_closeActiveDbSession`: call `rangeSessionView.markActivity()`.
- All safety-critical sections left untouched (STOP-flood guard, 8s scan timeout, SNAP reconcile).

Full new file:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/drill_config.dart';
import '../models/drill_session.dart';
import '../models/session_event.dart';
import '../models/session_record.dart';
import '../models/target_unit.dart';
import '../repositories/drill_template_repository.dart';
import '../repositories/session_repository.dart';
import '../services/audio_service.dart';
import '../services/ble_service.dart';
import '../services/config_hasher.dart';
import '../services/event_batcher.dart';
import '../services/preferences_repository.dart';
import '../services/range_session_view.dart';
import '../services/transmitter_protocol.dart';
import '../services/tts_port.dart';
import 'shooter_state.dart';

enum DrillPhase {
  idle,
  arming,
  running,
  stopping,
  finished,
  armingFailed,
}

class AppState extends ChangeNotifier {
  final BleService bleService = BleService();

  // --- Domain state (plan-1) ---
  List<TargetUnit> targets = [];
  bool isScanning = false;
  DrillSession? currentSession;
  final Set<int> unreachableTargets = {};

  // --- Gate-2 additions ---
  final PreferencesRepository? preferences;
  final AudioService? audio;
  final TtsPort? tts;
  final RangeSessionView? rangeSessionView;
  final DrillTemplateRepository? drillTemplates;

  Map<int, String> _targetNames = <int, String>{};
  Set<int> _removedTargetIds = <int>{};
  bool _showRemoved = false;
  bool _onboardingComplete = false;
  bool _readyChimePlayedForCurrentCycle = false;
  bool _discoveryDoneSeenForCurrentCycle = false;

  Map<int, String> get targetNames => Map.unmodifiable(_targetNames);
  Set<int> get removedTargetIds => Set.unmodifiable(_removedTargetIds);
  bool get showRemoved => _showRemoved;
  bool get onboardingComplete => _onboardingComplete;

  // --- Phase machine + telemetry (plan-1) ---
  DrillPhase _phase = DrillPhase.idle;
  DrillPhase get phase => _phase;

  StreamSubscription<String>? _dataSub;
  StreamSubscription<ConnectionStatus>? _statusSub;
  Timer? _armingTimeout;
  Timer? _stoppingTimeout;
  Timer? _scanTimeout;
  ConnectionStatus _lastStatus = ConnectionStatus.disconnected;

  final SessionRepository? _sessions;
  final ShooterState? _shooterState;
  EventBatcher? _batcher;
  String? _activeDbSessionId;
  int _iterationsCompleted = 0;
  Future<void>? _pendingClose;

  AppState._internal({
    SessionRepository? sessions,
    ShooterState? shooterState,
    this.preferences,
    this.audio,
    this.tts,
    this.rangeSessionView,
    this.drillTemplates,
  })  : _sessions = sessions,
        _shooterState = shooterState {
    _dataSub = bleService.incomingData.listen(_handleIncomingData);
    _statusSub = bleService.connectionStatus.listen(_handleConnectionStatus);
  }

  factory AppState({
    SessionRepository? sessions,
    ShooterState? shooterState,
    PreferencesRepository? preferences,
    AudioService? audio,
    TtsPort? tts,
    RangeSessionView? rangeSessionView,
    DrillTemplateRepository? drillTemplates,
  }) =>
      AppState._internal(
        sessions: sessions,
        shooterState: shooterState,
        preferences: preferences,
        audio: audio,
        tts: tts,
        rangeSessionView: rangeSessionView,
        drillTemplates: drillTemplates,
      );

  @visibleForTesting
  factory AppState.forTesting({
    required SessionRepository sessions,
    required ShooterState shooterState,
    PreferencesRepository? preferences,
    AudioService? audio,
    TtsPort? tts,
    RangeSessionView? rangeSessionView,
    DrillTemplateRepository? drillTemplates,
  }) =>
      AppState._internal(
        sessions: sessions,
        shooterState: shooterState,
        preferences: preferences,
        audio: audio,
        tts: tts,
        rangeSessionView: rangeSessionView,
        drillTemplates: drillTemplates,
      );

  // --- Hydrate gate-2 prefs on startup ---
  Future<void> hydratePreferences() async {
    final prefs = preferences;
    if (prefs == null) return;
    _targetNames = await prefs.getTargetNames();
    _removedTargetIds = await prefs.getRemovedTargetIds();
    _onboardingComplete = await prefs.isOnboardingComplete();
    notifyListeners();
  }

  // --- Target-name + removed-target API (gate-2) ---
  Future<void> setTargetName(int id, String? name) async {
    await preferences?.setTargetName(id, name);
    if (name == null || name.isEmpty) {
      _targetNames.remove(id);
    } else {
      _targetNames[id] = name;
    }
    notifyListeners();
  }

  Future<void> markTargetRemoved(int id) async {
    _removedTargetIds.add(id);
    await preferences?.setRemovedTargetIds(_removedTargetIds);
    notifyListeners();
  }

  Future<void> unmarkTargetRemoved(int id) async {
    _removedTargetIds.remove(id);
    await preferences?.setRemovedTargetIds(_removedTargetIds);
    notifyListeners();
  }

  void toggleShowRemoved() {
    _showRemoved = !_showRemoved;
    notifyListeners();
  }

  // --- Onboarding (gate-2) ---
  Future<void> markOnboardingComplete() async {
    _onboardingComplete = true;
    await preferences?.setOnboardingComplete(true);
    notifyListeners();
  }

  // --- Phase machine internals (plan-1 — untouched) ---
  void _setPhase(DrillPhase next) {
    if (_phase == next) return;
    _phase = next;
    notifyListeners();
  }

  void _handleConnectionStatus(ConnectionStatus status) {
    final prev = _lastStatus;
    _lastStatus = status;

    final wasReconnecting = prev == ConnectionStatus.reconnecting;
    final isNowConnected = status == ConnectionStatus.connected;
    final drillLive = _phase == DrillPhase.arming ||
        _phase == DrillPhase.running ||
        _phase == DrillPhase.stopping;

    if (wasReconnecting && isNowConnected && drillLive) {
      // Note: BleService also sends SNAP/ itself on reconnect; this is a
      // belt-and-suspenders safeguard in case BleService's auto-SNAP fails.
      unawaited(_sendSnap());
    }
  }

  Future<void> _sendSnap() async {
    try {
      await bleService.write(TransmitterProtocol.encodeSnap());
    } catch (_) {
      // Best-effort; no phase change on failure.
    }
  }

  void _handleIncomingData(String message) {
    final decoded = TransmitterProtocol.decodeTelemetry(message);

    if (decoded is DiscoveredTarget) {
      final existing = targets.where((t) => t.id == decoded.id);
      if (existing.isEmpty) {
        targets.add(TargetUnit(id: decoded.id, isOnline: true));
      } else {
        existing.first.isOnline = true;
      }
      notifyListeners();
      return;
    }

    if (decoded is DiscoveryDone) {
      _scanTimeout?.cancel();
      _scanTimeout = null;
      isScanning = false;
      _discoveryDoneSeenForCurrentCycle = true;
      // Gate-2 #15: play the "ready" chime once per discovery cycle.
      if (!_readyChimePlayedForCurrentCycle) {
        _readyChimePlayedForCurrentCycle = true;
        unawaited(audio?.playReadyChime());
      }
      notifyListeners();
      return;
    }

    if (decoded is StopAck) {
      _stoppingTimeout?.cancel();
      _stoppingTimeout = null;
      final session = currentSession;
      if (session != null && session.isRunning) {
        session.addEvent(SessionEvent(type: EventType.drillFinished));
      }
      _setPhase(DrillPhase.finished);
      unawaited(_closeActiveDbSession(finishedNormally: false));
      return;
    }

    if (decoded is UnreachableTarget) {
      unreachableTargets.add(decoded.id);
      notifyListeners();
      return;
    }

    if (decoded is SnapReply) {
      if (decoded.running) {
        if (_phase == DrillPhase.arming || _phase == DrillPhase.stopping) {
          _setPhase(DrillPhase.running);
        }
      } else {
        final session = currentSession;
        if (session != null && session.isRunning) {
          session.addEvent(SessionEvent(type: EventType.drillFinished));
        }
        _armingTimeout?.cancel();
        _stoppingTimeout?.cancel();
        _setPhase(DrillPhase.finished);
        unawaited(_closeActiveDbSession(finishedNormally: false));
      }
      return;
    }

    if (decoded is SessionEvent) {
      if (decoded.type == EventType.targetActivated &&
          _phase == DrillPhase.arming) {
        _armingTimeout?.cancel();
        _armingTimeout = null;
        _setPhase(DrillPhase.running);
      }
      if (currentSession != null) {
        currentSession!.addEvent(decoded);
        _batcher?.add(decoded);
        if (decoded.type == EventType.targetActivated) {
          _iterationsCompleted++;
        }
        if (decoded.type == EventType.drillFinished) {
          _armingTimeout?.cancel();
          _stoppingTimeout?.cancel();
          _setPhase(DrillPhase.finished);
          unawaited(_closeActiveDbSession(finishedNormally: true));
        }
        notifyListeners();
      }
    }
  }

  Future<void> discoverTargets() async {
    isScanning = true;
    _readyChimePlayedForCurrentCycle = false;
    _discoveryDoneSeenForCurrentCycle = false;
    for (final t in targets) {
      t.isOnline = false;
    }
    notifyListeners();
    _scanTimeout?.cancel();
    _scanTimeout = Timer(const Duration(seconds: 8), () {
      if (isScanning) {
        isScanning = false;
        notifyListeners();
      }
    });
    await bleService.write(TransmitterProtocol.encodeDiscovery());
  }

  Future<void> identifyTarget(int targetId) async {
    await bleService.write(TransmitterProtocol.encodeIdentify(targetId));
  }

  void resetDrillPhase() {
    _armingTimeout?.cancel();
    _stoppingTimeout?.cancel();
    _armingTimeout = null;
    _stoppingTimeout = null;
    _setPhase(DrillPhase.idle);
  }

  Future<void> startDrill(DrillConfig config) async {
    currentSession = DrillSession(config: config);
    unreachableTargets.clear();
    _iterationsCompleted = 0;
    _setPhase(DrillPhase.arming);

    unawaited(rangeSessionView?.markActivity());

    final sessions = _sessions;
    final shooterState = _shooterState;
    if (sessions != null && shooterState != null && shooterState.current != null) {
      final id = const Uuid().v4();
      _activeDbSessionId = id;
      final programCode =
          config.programType == ProgramType.programA ? 'A' : 'B';
      await sessions.insert(SessionRecord(
        id: id,
        shooterId: shooterState.current!.id,
        programType: programCode,
        configJson: ConfigHasher.canonicalJson(config),
        configHash: ConfigHasher.hash(config),
        startedAt: DateTime.now(),
        finishedNormally: false,
        iterationsCompleted: 0,
      ));
      _batcher = EventBatcher(
        onFlush: (events) => sessions.appendEvents(id, events),
      )..start();
    }

    _armingTimeout?.cancel();
    _armingTimeout = Timer(const Duration(seconds: 3), () {
      if (_phase == DrillPhase.arming) {
        _setPhase(DrillPhase.armingFailed);
      }
    });

    try {
      await bleService.write(TransmitterProtocol.encodeDrillStart(config));
    } catch (_) {
      // See plan-1 comment: arming timeout covers this.
    }
  }

  Future<void> stopDrill() async {
    // SAFETY-CRITICAL (e7f926b): guard BOTH the state transition AND the
    // wire write. Without this guard the write fired unconditionally — any
    // caller that invoked stopDrill() while phase was already
    // stopping/finished/idle would still blast STOP/ at the transmitter.
    if (_phase != DrillPhase.running && _phase != DrillPhase.arming) {
      return;
    }
    _setPhase(DrillPhase.stopping);
    _stoppingTimeout?.cancel();
    _stoppingTimeout = Timer(const Duration(seconds: 5), () {
      if (_phase == DrillPhase.stopping) {
        final session = currentSession;
        if (session != null && session.isRunning) {
          session.addEvent(SessionEvent(type: EventType.drillFinished));
        }
        _setPhase(DrillPhase.finished);
        unawaited(_closeActiveDbSession(finishedNormally: false));
      }
    });
    await bleService.write(TransmitterProtocol.encodeStop());
  }

  void forceDrillFinished() {
    final session = currentSession;
    if (session != null && session.isRunning) {
      session.addEvent(SessionEvent(type: EventType.drillFinished));
    }
    _armingTimeout?.cancel();
    _stoppingTimeout?.cancel();
    _setPhase(DrillPhase.finished);
    unawaited(_closeActiveDbSession(finishedNormally: false));
  }

  Future<void> _closeActiveDbSession({required bool finishedNormally}) async {
    unawaited(rangeSessionView?.markActivity());
    final id = _activeDbSessionId;
    final sessions = _sessions;
    final batcher = _batcher;
    if (id == null || sessions == null) return;
    if (batcher != null) {
      await batcher.stop();
    }
    await sessions.closeSession(
      id: id,
      endedAt: DateTime.now(),
      finishedNormally: finishedNormally,
      iterationsCompleted: _iterationsCompleted,
    );
    _activeDbSessionId = null;
    _batcher = null;
  }

  @visibleForTesting
  void handleSessionEventForTesting(SessionEvent event) {
    if (currentSession != null) {
      currentSession!.addEvent(event);
      _batcher?.add(event);
      if (event.type == EventType.targetActivated) {
        _iterationsCompleted++;
      }
      if (event.type == EventType.drillFinished) {
        _pendingClose = _closeActiveDbSession(finishedNormally: true);
      }
    }
  }

  @visibleForTesting
  void handleSnapReplyForTesting({required bool running}) {
    if (running) {
      if (_phase == DrillPhase.arming || _phase == DrillPhase.stopping) {
        _setPhase(DrillPhase.running);
      }
      return;
    }
    final session = currentSession;
    if (session != null && session.isRunning) {
      session.addEvent(SessionEvent(type: EventType.drillFinished));
    }
    _armingTimeout?.cancel();
    _stoppingTimeout?.cancel();
    _setPhase(DrillPhase.finished);
    final closeFuture = _closeActiveDbSession(finishedNormally: false);
    _pendingClose = closeFuture;
    unawaited(closeFuture);
  }

  @visibleForTesting
  Future<void> forceFlushForTesting() async {
    final id = _activeDbSessionId;
    final sessions = _sessions;
    final batcher = _batcher;
    if (batcher != null) {
      await batcher.stop();
      if (id != null && sessions != null && identical(_batcher, batcher)) {
        _batcher = EventBatcher(
          onFlush: (events) => sessions.appendEvents(id, events),
        )..start();
      }
    }
    await _pendingClose;
  }

  @override
  void dispose() {
    _armingTimeout?.cancel();
    _stoppingTimeout?.cancel();
    _dataSub?.cancel();
    _statusSub?.cancel();
    bleService.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 3: Run the safety-critical signature check**

Run: `./tool/check_safety_critical.sh`
Expected: `All 11 signatures present.`

- [ ] **Step 4: Run existing AppState tests (the plan-1 ones)**

Run: `flutter test test/state/ 2>&1 | tail -30`
Expected: existing tests still pass. No references to the removed gate-2 Hive types.

- [ ] **Step 5: Run `flutter analyze lib/state/app_state.dart`**

Expected: 0 issues. Fix any lint / import warnings inline.

- [ ] **Step 6: Commit**

```bash
git add lib/state/app_state.dart
git commit -m "refactor(state): layer gate-2 fields onto plan-1 AppState

Adds preferences/audio/tts/rangeSessionView/drillTemplates DI alongside
the existing sessions/shooterState. Gate-2 target-name/removed-target/
onboarding state hydrated via hydratePreferences(). Ready-chime fires
once per discovery cycle on DiscoveryDone. startDrill and
_closeActiveDbSession stamp rangeSessionView.markActivity().

Preserves all 6 safety-critical fixes from e7f926b (verified by
tool/check_safety_critical.sh):
- STOP-flood guard in stopDrill()
- 8s scan timeout
- SNAP/ reconcile on reconnect
- Nav listener detach stays in screens (Phase 3)
- 800ms STOP hold stays in drill_running_screen (Phase 3)
- Program B discoverTargets entry stays in screen (Phase 3)"
```

---

### Task 2.13: Wire up `main.dart` — drop Hive init, register new services

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Read current main.dart**

Run: `cat lib/main.dart`

The merge brought in gate-2's Hive-initializing version. We rewrite it clean.

- [ ] **Step 2: Replace `lib/main.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db/database_helper.dart';
import 'repositories/drill_template_repository.dart';
import 'repositories/session_repository.dart';
import 'repositories/shooter_repository.dart';
import 'screens/home_screen.dart';
import 'services/audio_service.dart';
import 'services/preferences_repository.dart';
import 'services/range_session_view.dart';
import 'services/tts_port.dart';
import 'state/app_state.dart';
import 'state/shooter_state.dart';
import 'theme/atriarch_theme.dart';
import 'theme/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Web preview bypass: no sqflite on web, no platform channels.
  if (kIsWeb) {
    runApp(const _WebPreviewApp());
    return;
  }

  final db = await DatabaseHelper.open();
  final prefs = await SharedPreferences.getInstance();
  final preferences = PreferencesRepository(prefs);
  final sessions = SessionRepository(db);
  final shooters = ShooterRepository(db);
  final drillTemplates = DrillTemplateRepository(db);
  final rangeView = RangeSessionView(
    sessions: sessions,
    preferences: preferences,
  );
  final audio = AudioService()..init();
  final tts = await FlutterTtsPort.create();
  final shooterState = ShooterState(shooters)..load();
  final themeController = ThemeController();

  final appState = AppState(
    sessions: sessions,
    shooterState: shooterState,
    preferences: preferences,
    audio: audio,
    tts: tts,
    rangeSessionView: rangeView,
    drillTemplates: drillTemplates,
  );
  await appState.hydratePreferences();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: shooterState),
        ChangeNotifierProvider.value(value: themeController),
      ],
      child: const AtriarchApp(),
    ),
  );
}

class AtriarchApp extends StatelessWidget {
  const AtriarchApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return MaterialApp(
      title: 'Atriarch',
      theme: buildAtriarchTheme(),
      darkTheme: buildAtriarchTheme(),
      themeMode: theme.themeMode,
      home: const HomeScreen(),
    );
  }
}

class _WebPreviewApp extends StatelessWidget {
  const _WebPreviewApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: buildAtriarchTheme(),
        darkTheme: buildAtriarchTheme(),
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: Center(
            child: Text('Atriarch web preview — tactical theme only'),
          ),
        ),
      );
}
```

(Note: `AtriarchTheme` / `buildAtriarchTheme` is the existing tactical theme factory. If the symbol name differs in `lib/theme/atriarch_theme.dart`, adjust. Verify with `grep -n 'ThemeData' lib/theme/atriarch_theme.dart`.)

- [ ] **Step 3: If `buildAtriarchTheme` doesn't exist under that name, find the real one and use it**

Run: `grep -n 'ThemeData\s*build\|ThemeData\s*get\|static ThemeData' lib/theme/atriarch_theme.dart`

Replace `buildAtriarchTheme()` calls in `main.dart` with the actual factory name (commonly `AtriarchTheme.dark()` or `atriarchDarkTheme`).

- [ ] **Step 4: Run analyze on main.dart**

Run: `flutter analyze lib/main.dart 2>&1 | tail -10`
Expected: 0 issues (or just import-order lint — auto-fix with `dart format`).

- [ ] **Step 5: Run the test suite to confirm nothing structural broke**

Run: `flutter test 2>&1 | tail -20`
Expected: majority pass. Any still-failing tests are gate-2 widget tests we haven't rewritten yet — those land in Phase 4. Target ≥85% pass rate at this Phase 2 exit point.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart
git commit -m "refactor(main): wire SQLite + shared_preferences + audio/tts services

Drops Hive.initFlutter() and all Hive adapter registration. Constructs
the new services (DrillTemplateRepository, RangeSessionView,
PreferencesRepository) from plan-1's SQLite DB + shared_preferences.
AppState.hydratePreferences() runs before runApp so first frame has
correct onboarding/target-name state."
```

---

### Task 2.14: Phase 2 exit — analyze clean, 6 safety signatures present

- [ ] **Step 1: Final analyze**

Run: `flutter analyze 2>&1 | tail -5`
Expected: `No issues found!`

- [ ] **Step 2: Safety signature sweep**

Run: `./tool/check_safety_critical.sh`
Expected: `All 11 signatures present.`

- [ ] **Step 3: Test pass-rate check**

Run: `flutter test 2>&1 | tail -5`

Note the pass/fail count. A ~20-40% gate-2 widget-test failure rate is expected here — those tests reference the deleted gate-2 Hive repos and will be rewritten in Phase 4. Plan-1 repo tests, AppState tests, and all tactical widget tests MUST still pass.

Fail this task if any non-gate-2 test is broken.

- [ ] **Step 4: Commit a "Phase 2 complete" marker**

```bash
git commit --allow-empty -m "chore(stage-3): Phase 2 exit — data layer on SQLite+shared_preferences

flutter analyze: clean
Safety-critical signatures: all 11 present (tool/check_safety_critical.sh)
Known failures: gate-2 widget tests (rewritten in Phase 4).

Ready for Phase 3 (screen conflicts + tactical retrofit)."
```

---

## Phase 3: Screen Conflicts + Tactical Retrofit

Goal: every screen from gate-2 compiles on the merged tree AND wears tactical visual language. All 6 safety-critical signatures survive. App launches (Chrome preview counts).

For each screen task: read the gate-2 version at `.worktrees/gate-2/lib/screens/<file>.dart` for feature semantics, then apply tactical styling using the widget library at `lib/widgets/tactical/`.

### **Execution order (widgets before screens that consume them)**

The task numbering below is by file-group, NOT by dependency. The correct execution order is:

1. **Tactical widgets first** (Tasks 3.9 → 3.10 → 3.11 → 3.12): `preset_row`, `target_actions_sheet`, `drill_share_sheet`, `drill_result_image`. These are consumed by the screens.
2. **Screens that consume those widgets** (Tasks 3.1 → 3.2 → 3.3 → 3.4 → 3.5): `home_screen`, `program_a_setup`, `program_b_setup`, `drill_running` (verify-only), `results_screen`.
3. **Stub-to-tactical rewrites of standalone screens** (Tasks 3.6 → 3.7 → 3.8): `settings_screen`, `recent_drills_screen`, onboarding 5 files.
4. **Phase 3 exit** (Task 3.13).

Rationale: Tasks 3.2/3.3 import `PresetRow` + `TargetActionsSheet`. Task 3.5 imports `DrillShareSheet`. Those widgets exist only as Phase-2 stubs at Phase-3 start — tactically rebuild them before screens integrate them. If you do screens first, you'll commit screens that wire against stubs, then have to re-edit the screens when the real widgets land.

---

### Task 3.1: `home_screen.dart` — add gate-2 nav entries to tactical dashboard

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: Read both versions**

```bash
head -100 lib/screens/home_screen.dart            # current (tactical)
head -100 .worktrees/gate-2/lib/screens/home_screen.dart   # gate-2 (pre-tactical)
```

Note gate-2's new nav destinations:
- Settings (`SettingsScreen()`)
- Recent Drills (`RecentDrillsScreen()`)
- Walk-the-Range flow (likely via an "Identify targets" button)
- Onboarding entry (if not yet complete)

- [ ] **Step 2: Pick the tactical home_screen as the base and add nav tiles for gate-2's three new destinations**

Find a natural grouping in the tactical home layout. If there's an overflow/menu pattern, use that; otherwise add a `TacticalSection` at the bottom titled `NAV_00 // UTILITIES` with three rows built from `TacticalPrimaryButton` or `TacticalCard`:

```dart
TacticalSection(
  code: 'NAV_00',
  title: 'UTILITIES',
  children: [
    TacticalPrimaryButton(
      label: 'RECENT_DRILLS',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RecentDrillsScreen()),
      ),
    ),
    const SizedBox(height: 8),
    TacticalPrimaryButton(
      label: 'SETTINGS',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
    ),
    const SizedBox(height: 8),
    TacticalPrimaryButton(
      label: 'WALK_THE_RANGE',
      onPressed: () => _startWalkTheRange(context),
    ),
  ],
),
```

- [ ] **Step 3: Implement `_startWalkTheRange(BuildContext)` at the end of the State class**

Port gate-2's walk-the-range trigger: iterate targets; for each, call `state.identifyTarget(id)` with a short pause, and `state.tts?.speak('Target <name-or-id>')`. Keep it minimal — the full interaction is in the target_actions_sheet.

```dart
Future<void> _startWalkTheRange(BuildContext context) async {
  final state = context.read<AppState>();
  final resolver = TargetNameResolver(state.targetNames);
  for (final target in state.targets.where((t) => t.isOnline)) {
    final name = resolver.nameFor(target.id);
    await state.tts?.speak(name);
    await state.identifyTarget(target.id);
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}
```

- [ ] **Step 4: If `_onboardingComplete` is false, route new launches to onboarding**

In `home_screen.dart` `build()` (or a `FirstRunGate` wrapper — whichever gate-2 used), check `state.onboardingComplete`. If false, build `OnboardingFlow()` instead of the main home layout.

```dart
@override
Widget build(BuildContext context) {
  final state = context.watch<AppState>();
  if (!state.onboardingComplete) {
    return const OnboardingFlow();
  }
  // ... existing tactical home layout ...
}
```

- [ ] **Step 5: Run analyze + test this file's tests**

Run: `flutter analyze lib/screens/home_screen.dart` then `flutter test test/screens/home_screen_test.dart 2>&1 | tail -5`
Expected: analyze clean; any screen test still passes (updates land in Phase 4 if needed).

- [ ] **Step 6: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat(home): add gate-2 nav entries (Settings, Recent Drills, Walk-the-Range)

Tactical layout preserved. New utilities section uses
TacticalPrimaryButton rows. First-launch routes to OnboardingFlow when
preferences.onboarding_complete is false."
```

---

### Task 3.2: `program_a_setup_screen.dart` — 3-way: tactical + ShooterChip + PresetRow + target-actions

**Files:**
- Modify: `lib/screens/program_a_setup_screen.dart`

- [ ] **Step 1: Read both versions to understand the surface**

```bash
wc -l lib/screens/program_a_setup_screen.dart .worktrees/gate-2/lib/screens/program_a_setup_screen.dart
grep -n 'PresetRow\|TargetActionsSheet\|ShooterChip' lib/screens/program_a_setup_screen.dart .worktrees/gate-2/lib/screens/program_a_setup_screen.dart
```

Plan-1's ShooterChip is in the body header (moved from AppBar after overflow fix). Gate-2's PresetRow sits above the form. Gate-2's long-press-on-GroupNodeCard opens TargetActionsSheet.

- [ ] **Step 2: Restructure the ListView children to `[ShooterChip, _header, PresetRow, ...tactical-sections]`**

Inside the existing tactical scaffold, arrange top-of-body:

```dart
body: ListView(
  padding: const EdgeInsets.all(16),
  children: [
    ShooterChipHeader(shooterState: shooterState),
    const SizedBox(height: 12),
    _buildTacticalHeader(),                 // existing tactical header
    const SizedBox(height: 8),
    PresetRow(
      onLoad: _applyPreset,
      onSave: _promptSavePresetName,
      drillTemplates: context.read<AppState>().drillTemplates!,
      currentConfig: _currentConfigSnapshot(),
    ),
    const SizedBox(height: 16),
    ...buildTacticalSections(),              // existing min/max cards + group cards
  ],
)
```

- [ ] **Step 3: Wire up `_applyPreset(DrillTemplate)` and `_promptSavePresetName()`**

`_applyPreset` pushes the template's `DrillConfig` values into the existing controllers. `_promptSavePresetName` shows a simple `AlertDialog` asking for a name, then calls:

```dart
Future<void> _savePresetWithName(String name) async {
  final state = context.read<AppState>();
  final repo = state.drillTemplates!;
  final config = _currentConfigSnapshot();
  final id = const Uuid().v4();
  final template = DrillTemplate(
    id: id,
    shooterId: null, // gate-2 save flow: app-wide
    name: name.trim(),
    programType: ProgramType.programA,
    config: config,
    configHash: ConfigHasher.hash(config),
    createdAt: DateTime.now(),
  );
  await repo.insert(template);
  setState(() {});
}
```

- [ ] **Step 4: Long-press on GroupNodeCard opens TargetActionsSheet**

On each `GroupNodeCard`, wrap the widget with `GestureDetector(onLongPress: () => _openTargetActions(card.targetIds))`.

`_openTargetActions`:

```dart
void _openTargetActions(List<int> targetIds) {
  showModalBottomSheet(
    context: context,
    builder: (_) => TargetActionsSheet(targetIds: targetIds),
  );
}
```

TargetActionsSheet already exists (ported from gate-2); it hosts identify / rename / remove / restore actions wired to AppState.

- [ ] **Step 5: PRESERVE the safety-critical nav listener detach**

Find the `_onPhaseChanged` method. Verify its Navigator.pushReplacement path calls `state.removeListener(_onPhaseChanged)` BEFORE pushing:

```dart
void _onPhaseChanged() {
  final state = _boundState!;
  if (state.phase == DrillPhase.finished) {
    state.removeListener(_onPhaseChanged);   // <-- SAFETY-CRITICAL
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ResultsScreen()),
    );
  }
}
```

Do not touch this line.

- [ ] **Step 6: Run the safety check and tests for this screen**

Run: `./tool/check_safety_critical.sh && flutter analyze lib/screens/program_a_setup_screen.dart`

Expected: all 11 signatures OK; 0 analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/program_a_setup_screen.dart
git commit -m "feat(program_a): 3-way merge — tactical + ShooterChip + PresetRow + long-press actions

ListView top: [ShooterChipHeader, _header, PresetRow,
...tacticalSections]. Long-press GroupNodeCard → TargetActionsSheet.
Save-as-preset inserts into drill_templates with shooter_id=null.
Nav listener detach preserved (safety-critical, e7f926b)."
```

---

### Task 3.3: `program_b_setup_screen.dart` — same 3-way pattern

**Files:**
- Modify: `lib/screens/program_b_setup_screen.dart`

- [ ] **Step 1: Apply the same pattern as Task 3.2**

Same ordering: ShooterChipHeader, _header, PresetRow, tactical sections (different content — Program B has NODE_SCAN flow). Wire long-press, save-preset, apply-preset identically.

- [ ] **Step 2: PRESERVE `state.discoverTargets()` reachable entry** (safety-critical fix #6)

Search for the existing `PARAM_00 // NODE_SCAN` button. Keep it callable:

```dart
TacticalPrimaryButton(
  label: 'NODE_SCAN',
  onPressed: () => state.discoverTargets(),
),
```

- [ ] **Step 3: PRESERVE `_onPhaseChanged` listener detach before nav**

Same as Task 3.2 Step 5.

- [ ] **Step 4: Run safety check + analyze**

Run: `./tool/check_safety_critical.sh && flutter analyze lib/screens/program_b_setup_screen.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/screens/program_b_setup_screen.dart
git commit -m "feat(program_b): 3-way merge — tactical + ShooterChip + PresetRow + scan button

Same layout as program_a with Program B's NODE_SCAN button preserved
as the discoverTargets entry point (safety-critical #6, e7f926b).
Nav listener detach preserved."
```

---

### Task 3.4: `drill_running_screen.dart` — preserve 6 safety fixes, minimal style

**Files:**
- Modify: `lib/screens/drill_running_screen.dart` (if any gate-2 additions slipped in; otherwise leave alone)

- [ ] **Step 1: Verify current (tactical) drill_running_screen is intact**

Run: `./tool/check_safety_critical.sh`
Expected: all 11 OK.

Specifically verify lines around:
- `_checkDrillComplete` method contains `state.removeListener(_checkDrillComplete)` BEFORE `Navigator.pushReplacement` (signature #1).
- `_StopButton` uses `Listener` + `AnimationController(duration: Duration(milliseconds: 800))` + `PopScope(canPop: false)` (signature #5).

- [ ] **Step 2: If anything changed, re-port from e7f926b and re-run the sweep. Otherwise: no action.**

- [ ] **Step 3: Commit (empty checkpoint if no file changes)**

```bash
git commit --allow-empty -m "chore(drill-running): verified 6 safety-critical fixes intact post-merge"
```

---

### Task 3.5: `results_screen.dart` — tactical dossier + share sheet

**Files:**
- Modify: `lib/screens/results_screen.dart`

- [ ] **Step 1: Read both versions**

```bash
head -50 lib/screens/results_screen.dart .worktrees/gate-2/lib/screens/results_screen.dart
```

- [ ] **Step 2: Keep tactical dossier layout; add a tactical footer action "Share"**

In the footer/bottom-action area of the tactical scaffold, add:

```dart
TacticalPrimaryButton(
  label: 'SHARE',
  onPressed: () async {
    final state = context.read<AppState>();
    final sessionId = state._activeDbSessionId;   // or track via a getter
    if (sessionId == null) return;
    final events = await state._sessions!.getEventsFor(sessionId);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (_) => DrillShareSheet(
        events: events,
        config: state.currentSession!.config,
      ),
    );
  },
),
```

Expose a public getter on AppState if `_activeDbSessionId` is still private:

```dart
String? get activeSessionId => _activeDbSessionId;
SessionRepository? get sessions => _sessions;
```

(Add to AppState, re-run analyze.)

- [ ] **Step 3: Run analyze + safety check**

Run: `flutter analyze lib/screens/results_screen.dart lib/state/app_state.dart && ./tool/check_safety_critical.sh`

- [ ] **Step 4: Commit**

```bash
git add lib/screens/results_screen.dart lib/state/app_state.dart
git commit -m "feat(results): tactical dossier + share-sheet footer action

Events loaded via SessionRepository.getEventsFor (new read method in
Task 2.4) — replaces gate-2's deleted DrillLogRepository path."
```

---

### Task 3.6: `settings_screen.dart` — tactical retrofit, NO theme toggle

**Files:**
- Rewrite: `lib/screens/settings_screen.dart`

- [ ] **Step 1: Read gate-2's version for the list of toggles**

Run: `cat .worktrees/gate-2/lib/screens/settings_screen.dart`

Note the toggles gate-2 ships (theme radio excluded per Stage-3 gate). Likely remaining: "Show removed targets" toggle, "Reset onboarding" debug button, "Clear range session" button.

- [ ] **Step 2: Rewrite as a TacticalScaffold**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/tactical/tactical_app_bar.dart';
import '../widgets/tactical/tactical_primary_button.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return TacticalScaffold(
      appBar: const TacticalAppBar(title: 'SETTINGS'),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TacticalSection(
            code: 'SET_00',
            title: 'TARGETS',
            children: [
              SwitchListTile(
                title: const Text('Show removed targets'),
                value: state.showRemoved,
                onChanged: (_) => state.toggleShowRemoved(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TacticalSection(
            code: 'SET_01',
            title: 'RANGE_SESSION',
            children: [
              TacticalPrimaryButton(
                label: 'CLEAR_CURRENT_SESSION',
                onPressed: () => state.rangeSessionView?.clearCurrent(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TacticalSection(
            code: 'SET_02',
            title: 'ONBOARDING',
            children: [
              TacticalPrimaryButton(
                label: 'REPLAY_ONBOARDING',
                onPressed: () async {
                  await state.preferences?.setOnboardingComplete(false);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Run analyze**

Run: `flutter analyze lib/screens/settings_screen.dart`
Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat(settings): tactical retrofit — no theme toggle (dark-only gate)

TacticalScaffold. Three sections (Targets, Range session, Onboarding).
Theme toggle dropped per Stage-3 gate (memory:
project_theme_dark_only.md). Replay onboarding resets the flag and
pops back to home."
```

---

### Task 3.7: `recent_drills_screen.dart` — tactical list driven by RangeSessionView

**Files:**
- Rewrite: `lib/screens/recent_drills_screen.dart`

- [ ] **Step 1: Read gate-2's version for row layout intent**

Run: `cat .worktrees/gate-2/lib/screens/recent_drills_screen.dart`

Note: gate-2 showed a list of `SessionSummary` items. We replace with `SessionRecord`s from RangeSessionView.

- [ ] **Step 2: Rewrite**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/session_record.dart';
import '../state/app_state.dart';
import '../widgets/tactical/tactical_app_bar.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_scaffold.dart';

class RecentDrillsScreen extends StatefulWidget {
  const RecentDrillsScreen({super.key});
  @override
  State<RecentDrillsScreen> createState() => _RecentDrillsScreenState();
}

class _RecentDrillsScreenState extends State<RecentDrillsScreen> {
  Future<List<SessionRecord>>? _future;

  @override
  void initState() {
    super.initState();
    final view = context.read<AppState>().rangeSessionView;
    _future = view?.listCurrent() ?? Future.value(<SessionRecord>[]);
  }

  @override
  Widget build(BuildContext context) {
    return TacticalScaffold(
      appBar: const TacticalAppBar(title: 'RECENT_DRILLS'),
      child: FutureBuilder<List<SessionRecord>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final drills = snap.data ?? const <SessionRecord>[];
          if (drills.isEmpty) {
            return const Center(
              child: Text('No drills in the current range session.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: drills.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final d = drills[i];
              return TacticalCard(
                child: ListTile(
                  title: Text('Program ${d.programType} — ${d.id.substring(0, 8)}'),
                  subtitle: Text(_fmt(d.startedAt)),
                  trailing: Text(
                    d.finishedNormally ? 'FIN' : 'INCOMPLETE',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
```

- [ ] **Step 3: Run analyze**

Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/recent_drills_screen.dart
git commit -m "feat(recent-drills): tactical list driven by RangeSessionView

Replaces gate-2's SessionSummary-driven version. listCurrent() returns
SessionRecord rows from SQLite filtered by the 8h cutoff."
```

---

### Task 3.8: Onboarding — retrofit 5 step files to TacticalScaffold

**Files:**
- Rewrite: `lib/screens/onboarding/welcome_step.dart`
- Rewrite: `lib/screens/onboarding/pair_transmitter_step.dart`
- Rewrite: `lib/screens/onboarding/discover_targets_step.dart`
- Rewrite: `lib/screens/onboarding/first_drill_step.dart`
- Rewrite: `lib/screens/onboarding/onboarding_flow.dart`

- [ ] **Step 1: Read gate-2 versions to preserve their semantics**

```bash
for f in welcome_step pair_transmitter_step discover_targets_step first_drill_step onboarding_flow; do
  echo "=== $f ==="
  head -40 ".worktrees/gate-2/lib/screens/onboarding/${f}.dart"
done
```

- [ ] **Step 2: For each step, wrap in `TacticalScaffold` with one `TacticalSection` per logical chunk**

Example `welcome_step.dart`:

```dart
import 'package:flutter/material.dart';

import '../../widgets/tactical/tactical_primary_button.dart';
import '../../widgets/tactical/tactical_scaffold.dart';
import '../../widgets/tactical/tactical_section.dart';

class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => TacticalScaffold(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              TacticalSection(
                code: 'ONB_00',
                title: 'WELCOME',
                children: [
                  const Text(
                    'Atriarch is a reactive target training system. '
                    'This quick setup will pair your transmitter, discover '
                    'your targets, and walk you through your first drill.',
                  ),
                ],
              ),
              const Spacer(),
              TacticalPrimaryButton(label: 'START_SETUP', onPressed: onNext),
            ],
          ),
        ),
      );
}
```

Apply the same retrofit to the other four files — preserve gate-2's interactive logic (scan button, first-drill config). Replace classic AppBar / MaterialButton with TacticalAppBar / TacticalPrimaryButton.

- [ ] **Step 3: Run analyze on the onboarding dir**

Run: `flutter analyze lib/screens/onboarding/`
Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/onboarding/
git commit -m "feat(onboarding): retrofit 5 step files to TacticalScaffold

Each step wraps its body in TacticalSection. AppBars converted to
TacticalAppBar; primary CTAs use TacticalPrimaryButton. Interactive
logic (scan, first drill config) preserved from gate-2."
```

---

### Task 3.9: `preset_row.dart` — tactical style

**Files:**
- Modify: `lib/widgets/preset_row.dart`

- [ ] **Step 1: Read gate-2's version**

Run: `cat .worktrees/gate-2/lib/widgets/preset_row.dart`

- [ ] **Step 2: Replace chrome Material styling with tactical widgets**

The row has three elements: dropdown of presets, "Load" button, "Save" button. Tactical-ize:

```dart
import 'package:flutter/material.dart';

import '../models/drill_config.dart';
import '../models/drill_template.dart';
import '../repositories/drill_template_repository.dart';
import 'tactical/tactical_card.dart';
import 'tactical/tactical_primary_button.dart';

class PresetRow extends StatefulWidget {
  const PresetRow({
    super.key,
    required this.drillTemplates,
    required this.currentConfig,
    required this.onLoad,
    required this.onSave,
  });

  final DrillTemplateRepository drillTemplates;
  final DrillConfig Function() currentConfig;
  final void Function(DrillTemplate) onLoad;
  final VoidCallback onSave;

  @override
  State<PresetRow> createState() => _PresetRowState();
}

class _PresetRowState extends State<PresetRow> {
  List<DrillTemplate> _templates = const [];
  DrillTemplate? _selected;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final list = await widget.drillTemplates.listAll();
    setState(() => _templates = list);
  }

  @override
  Widget build(BuildContext context) {
    return TacticalCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: DropdownButton<DrillTemplate>(
                isExpanded: true,
                value: _selected,
                hint: const Text('— PRESET —'),
                items: _templates
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                    .toList(),
                onChanged: (t) => setState(() => _selected = t),
              ),
            ),
            const SizedBox(width: 8),
            TacticalPrimaryButton(
              label: 'LOAD',
              onPressed: _selected == null ? null : () => widget.onLoad(_selected!),
            ),
            const SizedBox(width: 8),
            TacticalPrimaryButton(label: 'SAVE', onPressed: widget.onSave),
          ],
        ),
      ),
    );
  }
}
```

(Make sure `TacticalPrimaryButton.onPressed` accepts `null` to disable. If it doesn't, wrap the dropdown branch in `Opacity` + `IgnorePointer`.)

- [ ] **Step 3: Run analyze**

Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/preset_row.dart
git commit -m "feat(preset-row): tactical restyle + DrillTemplateRepository wiring

Dropdown of templates, Load/Save buttons. Callers pass currentConfig
and onLoad/onSave; the widget owns refreshing the list."
```

---

### Task 3.10: `target_actions_sheet.dart` — tactical style + new repo wiring

**Files:**
- Modify: `lib/widgets/target_actions_sheet.dart`

- [ ] **Step 1: Read gate-2's version to understand actions**

Actions: Identify, Rename, Mark removed / Unmark removed. Port with tactical buttons.

- [ ] **Step 2: Rewrite**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'tactical/tactical_primary_button.dart';

class TargetActionsSheet extends StatelessWidget {
  const TargetActionsSheet({super.key, required this.targetIds});
  final List<int> targetIds;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('TARGETS ${targetIds.join(", ")}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TacticalPrimaryButton(
              label: 'IDENTIFY',
              onPressed: () async {
                Navigator.pop(context);
                for (final id in targetIds) {
                  await state.identifyTarget(id);
                }
              },
            ),
            const SizedBox(height: 8),
            TacticalPrimaryButton(
              label: 'RENAME',
              onPressed: () => _rename(context, state),
            ),
            const SizedBox(height: 8),
            TacticalPrimaryButton(
              label: 'REMOVE',
              onPressed: () async {
                for (final id in targetIds) {
                  await state.markTargetRemoved(id);
                }
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, AppState state) async {
    if (targetIds.length != 1) return; // rename only for single target
    final id = targetIds.single;
    final controller = TextEditingController(
      text: state.targetNames[id] ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename target'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (name != null) {
      await state.setTargetName(id, name);
      if (context.mounted) Navigator.pop(context);
    }
  }
}
```

- [ ] **Step 3: Analyze + commit**

```bash
flutter analyze lib/widgets/target_actions_sheet.dart
git add lib/widgets/target_actions_sheet.dart
git commit -m "feat(target-actions): tactical restyle + rename via setTargetName"
```

---

### Task 3.11: `drill_share_sheet.dart` — tactical-style, event-driven

**Files:**
- Modify: `lib/widgets/drill_share_sheet.dart`

- [ ] **Step 1: Read gate-2's version to understand the share payload**

Gate-2 encoded a summary image + event list. We now take `List<SessionEvent>` directly.

- [ ] **Step 2: Rewrite `DrillShareSheet` to accept `events: List<SessionEvent>` + `config: DrillConfig`, render a tactical bottom-sheet with share button**

```dart
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/drill_config.dart';
import '../models/session_event.dart';
import '../util/drill_log_codec.dart';
import 'tactical/tactical_primary_button.dart';

class DrillShareSheet extends StatelessWidget {
  const DrillShareSheet({
    super.key,
    required this.events,
    required this.config,
  });
  final List<SessionEvent> events;
  final DrillConfig config;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('DRILL_SHARE', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TacticalPrimaryButton(
                label: 'COPY_LOG',
                onPressed: () async {
                  final text = DrillLogCodec.encode(events: events, config: config);
                  await Share.share(text);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      );
}
```

- [ ] **Step 3: Update `lib/util/drill_log_codec.dart` to encode from a live event list**

Replace the codec body with a function that takes `events + config` and returns a text blob suitable for sharing:

```dart
import 'dart:convert';

import '../models/drill_config.dart';
import '../models/session_event.dart';

class DrillLogCodec {
  static String encode({
    required List<SessionEvent> events,
    required DrillConfig config,
  }) {
    final map = {
      'version': 1,
      'program_type': config.programType == ProgramType.programA ? 'A' : 'B',
      'events': events
          .map((e) => {
                'type': e.type.name,
                'target_id': e.targetId,
                'hit_number': e.hitNumber,
                'ts_ms': e.timestamp.millisecondsSinceEpoch,
              })
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }
}
```

- [ ] **Step 4: Analyze + commit**

```bash
flutter analyze lib/widgets/drill_share_sheet.dart lib/util/drill_log_codec.dart
git add lib/widgets/drill_share_sheet.dart lib/util/drill_log_codec.dart
git commit -m "feat(drill-share): tactical restyle + event-driven codec

DrillLogCodec.encode now takes live events+config (read via
SessionRepository.getEventsFor). gate-2's blob-based
DrillLogRepository flow is gone."
```

---

### Task 3.12: `drill_result_image.dart` — tactical style

**Files:**
- Modify: `lib/widgets/drill_result_image.dart`

- [ ] **Step 1: Read gate-2's version**

Run: `head -60 .worktrees/gate-2/lib/widgets/drill_result_image.dart`

- [ ] **Step 2: Port the widget, replacing Material surfaces with tactical tokens**

Primary change: background color uses tactical dark, accent color uses `AtriarchTokens.statusLive`, typography uses the tactical text-theme. Logic stays the same (draw title + key stats to a Widget).

Implementation specifics depend on gate-2's drawing approach; keep its geometry + substitute colors.

- [ ] **Step 3: Analyze + commit**

```bash
flutter analyze lib/widgets/drill_result_image.dart
git add lib/widgets/drill_result_image.dart
git commit -m "feat(drill-result-image): tactical color tokens"
```

---

### Task 3.13: Phase 3 exit — analyze clean, 6 safety signatures, app launches

- [ ] **Step 1: Final analyze**

Run: `flutter analyze 2>&1 | tail -5`
Expected: `No issues found!`

- [ ] **Step 2: Safety check**

Run: `./tool/check_safety_critical.sh`
Expected: `All 11 signatures present.`

- [ ] **Step 3: Chrome preview launch test**

Run: `flutter run -d chrome --release 2>&1 | tail -20 &`
Let it boot (~20s). Expected: `_WebPreviewApp` renders (because kIsWeb path in main.dart). Kill with `kill %1`.

- [ ] **Step 4: Commit phase-3 marker**

```bash
git commit --allow-empty -m "chore(stage-3): Phase 3 exit — screens retrofitted

flutter analyze: clean
Safety-critical signatures: all 11 present
Chrome preview: launches cleanly"
```

---

## Phase 4: Test Coverage Repair

Goal: gate-2's broken widget tests rewritten on fake-repo pattern. ≥95% of combined suite passes. One integration test covers the cross-cutting path.

### Task 4.1: Build `FakePreferencesRepository` in test/test_helpers/

**Files:**
- Create: `test/test_helpers/fake_preferences_repository.dart`

- [ ] **Step 1: Create the fake**

```dart
import 'package:atriarch/services/preferences_repository.dart';

class FakePreferencesRepository implements PreferencesRepository {
  String? _defaultPresetId;
  final Map<int, String> _targetNames = {};
  Set<int> _removedTargetIds = {};
  bool _onboardingComplete = false;
  DateTime? _lastRangeActivity;

  @override
  Future<String?> getDefaultPresetId() async => _defaultPresetId;

  @override
  Future<void> setDefaultPresetId(String? id) async => _defaultPresetId = id;

  @override
  Future<Map<int, String>> getTargetNames() async =>
      Map.from(_targetNames);

  @override
  Future<void> setTargetName(int targetId, String? displayName) async {
    if (displayName == null || displayName.isEmpty) {
      _targetNames.remove(targetId);
    } else {
      _targetNames[targetId] = displayName;
    }
  }

  @override
  Future<Set<int>> getRemovedTargetIds() async => Set.from(_removedTargetIds);

  @override
  Future<void> setRemovedTargetIds(Set<int> ids) async =>
      _removedTargetIds = Set.from(ids);

  @override
  Future<bool> isOnboardingComplete() async => _onboardingComplete;

  @override
  Future<void> setOnboardingComplete(bool v) async =>
      _onboardingComplete = v;

  @override
  Future<DateTime?> getLastRangeActivity() async => _lastRangeActivity;

  @override
  Future<void> setLastRangeActivity(DateTime t) async =>
      _lastRangeActivity = t;

  @override
  Future<void> clearLastRangeActivity() async => _lastRangeActivity = null;
}
```

- [ ] **Step 2: Commit**

```bash
git add test/test_helpers/fake_preferences_repository.dart
git commit -m "test(helpers): FakePreferencesRepository for widget tests"
```

---

### Task 4.2: Build `FakeDrillTemplateRepository` in test/test_helpers/

**Files:**
- Create: `test/test_helpers/fake_drill_template_repository.dart`

- [ ] **Step 1: Create the fake**

```dart
import 'package:atriarch/models/drill_template.dart';
import 'package:atriarch/repositories/drill_template_repository.dart';

class FakeDrillTemplateRepository implements DrillTemplateRepository {
  final Map<String, DrillTemplate> _byId = {};

  @override
  Future<void> insert(DrillTemplate t) async {
    if (_byId.containsKey(t.id)) {
      throw StateError('Template id ${t.id} already exists');
    }
    _byId[t.id] = t;
  }

  @override
  Future<void> upsert(DrillTemplate t) async => _byId[t.id] = t;

  @override
  Future<DrillTemplate?> getById(String id) async => _byId[id];

  @override
  Future<List<DrillTemplate>> listAll() async {
    final list = _byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Future<void> delete(String id) async => _byId.remove(id);
}
```

- [ ] **Step 2: Commit**

```bash
git add test/test_helpers/fake_drill_template_repository.dart
git commit -m "test(helpers): FakeDrillTemplateRepository for widget tests"
```

---

### Task 4.3: Build `FakeAudioService`

**Files:**
- Create: `test/test_helpers/fake_audio_service.dart`

- [ ] **Step 1: Create the fake**

```dart
import 'package:atriarch/services/audio_service.dart';

class FakeAudioService implements AudioService {
  int playCount = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> playReadyChime() async => playCount++;

  @override
  Future<void> dispose() async {}
}
```

(If the real `AudioService` surface differs, match its signatures exactly. Run `grep -n 'Future\|void' lib/services/audio_service.dart` to confirm.)

- [ ] **Step 2: Commit**

```bash
git add test/test_helpers/fake_audio_service.dart
git commit -m "test(helpers): FakeAudioService for widget tests"
```

---

### Task 4.4: Port `RecordingTtsPort` from gate-2 tests

**Files:**
- Create: `test/test_helpers/recording_tts_port.dart`

- [ ] **Step 1: Find gate-2's version**

Run: `grep -rn 'RecordingTtsPort' .worktrees/gate-2/test/`

- [ ] **Step 2: Copy to `test/test_helpers/recording_tts_port.dart`**

If the gate-2 file is already self-contained, copy verbatim. If it's inline, extract:

```dart
import 'package:atriarch/services/tts_port.dart';

class RecordingTtsPort implements TtsPort {
  final List<String> spoken = [];
  bool stopped = false;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stopped = true;
}
```

- [ ] **Step 3: Commit**

```bash
git add test/test_helpers/recording_tts_port.dart
git commit -m "test(helpers): RecordingTtsPort ported from gate-2 tests"
```

---

### Task 4.5: Rewrite gate-2's PreferencesRepository tests

Gate-2 had tests against Hive-backed PreferencesRepository at `test/data/preferences_repository_test.dart` (now deleted from lib/, possibly still in the git index from merge). The shared_preferences version is already tested in Task 2.7. Delete gate-2's old tests.

- [ ] **Step 1: Remove any stale test files**

```bash
rm -f test/data/preferences_repository_test.dart test/data/session_repository_test.dart test/data/drill_log_repository_test.dart test/data/drill_preset_test.dart
rmdir test/data 2>/dev/null || true
```

- [ ] **Step 2: Commit**

```bash
git add -A test/
git commit -m "test: remove gate-2 Hive-era data-layer tests

preferences_repository, session_repository (gate-2), drill_log_repository,
drill_preset — all replaced by SQLite/shared_preferences-backed tests
already landed earlier in Phase 2."
```

---

### Task 4.6: Rewrite gate-2 widget tests on fake-repo pattern

Identify gate-2 widget tests still failing:

- [ ] **Step 1: Run full test suite and capture failures**

```bash
flutter test 2>&1 | grep -E 'FAIL|failing' > /tmp/stage3_failures.txt
cat /tmp/stage3_failures.txt | head -40
```

- [ ] **Step 2: For each failing widget test, identify whether it's worth fixing**

Drop (delete) tests that assert on gate-2 UI that was replaced by tactical — they're obsolete. Keep tests that assert on behaviour we still ship (preset save, target rename, session list filtering).

For each kept test: rewire to use FakePreferencesRepository + FakeDrillTemplateRepository + FakeAudioService + RecordingTtsPort. Follow this pattern:

```dart
import 'package:atriarch/state/app_state.dart';
// ... existing imports ...
import '../../test_helpers/fake_preferences_repository.dart';
import '../../test_helpers/fake_drill_template_repository.dart';
import '../../test_helpers/fake_audio_service.dart';
import '../../test_helpers/recording_tts_port.dart';

AppState makeAppState({
  PreferencesRepository? preferences,
  DrillTemplateRepository? drillTemplates,
  AudioService? audio,
  TtsPort? tts,
}) =>
    AppState.forTesting(
      sessions: FakeSessionRepository(),   // existing helper if present, else InMemorySessionRepo
      shooterState: ShooterState(FakeShooterRepo([makeUnassignedShooter()]))..load(),
      preferences: preferences ?? FakePreferencesRepository(),
      drillTemplates: drillTemplates ?? FakeDrillTemplateRepository(),
      audio: audio ?? FakeAudioService(),
      tts: tts ?? RecordingTtsPort(),
    );
```

(If `FakeSessionRepository` doesn't exist yet, inline one — in-memory list + matching signatures.)

- [ ] **Step 3: Run the now-rewired widget tests iteratively until they pass**

For each test file: `flutter test test/<file>.dart -v 2>&1 | tail -30`. Fix, commit per file:

```bash
git add test/<file>.dart
git commit -m "test: rewire <feature> tests on fake-repo pattern"
```

- [ ] **Step 4: After all files addressed, run the full suite**

Run: `flutter test 2>&1 | tail -10`
Expected: ≥95% pass rate. Any surviving failure must be either (a) a legitimate bug to fix (fix before exit), or (b) an obsolete gate-2 test marked with `@Skip('obsolete: replaced by <new test>')` with justification in the commit.

---

### Task 4.7: Add one integration test — range-session → drill → persisted → listed

**Files:**
- Create: `test/integration/range_session_drill_flow_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'package:atriarch/constants.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/repositories/session_repository.dart';
import 'package:atriarch/services/preferences_repository.dart';
import 'package:atriarch/services/range_session_view.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/state/shooter_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/fake_shooter_repo.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('range session → drill → persisted → listed in RangeSessionView',
      () async {
    final db = await DatabaseHelper.openForTesting();
    final sessions = SessionRepository(db);
    final prefs = await SharedPreferences.getInstance();
    final preferences = PreferencesRepository(prefs);
    final rangeView = RangeSessionView(
      sessions: sessions,
      preferences: preferences,
    );

    final shooterRepo = FakeShooterRepo([makeUnassignedShooter()]);
    final shooterState = ShooterState(shooterRepo)..load();
    await shooterState.setCurrent(shooterRepo.listAll().then((l) => l.first)
        as dynamic); // load the unassigned shooter

    final appState = AppState.forTesting(
      sessions: sessions,
      shooterState: shooterState,
      preferences: preferences,
      rangeSessionView: rangeView,
    );

    // 1. Cold-start: no drills visible.
    expect(await rangeView.listCurrent(), isEmpty);

    // 2. Start a drill.
    final config = DrillConfig(programType: ProgramType.programA);
    await appState.startDrill(config);

    // 3. Simulate a finished drill via test hook.
    appState.handleSessionEventForTesting(
      SessionEvent(type: EventType.drillFinished),
    );
    await appState.forceFlushForTesting();

    // 4. Listed in the range-session view.
    final listed = await rangeView.listCurrent();
    expect(listed, hasLength(1));
    expect(listed.first.programType, 'A');
    expect(listed.first.finishedNormally, isTrue);

    await db.close();
  });
}
```

- [ ] **Step 2: Run and fix until green**

Run: `flutter test test/integration/range_session_drill_flow_test.dart -v`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/integration/range_session_drill_flow_test.dart
git commit -m "test(integration): range-session → drill → persisted → listed

Covers the cross-cutting path gate-2 + plan-1 deliver together. Hits
SQLite sessions table + shared_preferences cutoff + in-memory shooter
state without any Hive artifacts."
```

---

### Task 4.8: Phase 4 exit — ≥95% test pass rate, safety signatures intact

- [ ] **Step 1: Final test pass**

Run: `flutter test 2>&1 | tail -3`
Expected: `All tests passed!` OR ≥95% pass with all failures explicitly marked `@Skip`.

- [ ] **Step 2: Safety check**

Run: `./tool/check_safety_critical.sh`
Expected: `All 11 signatures present.`

- [ ] **Step 3: Analyze**

Run: `flutter analyze 2>&1 | tail -3`
Expected: `No issues found!`

- [ ] **Step 4: Commit phase-4 marker**

```bash
git commit --allow-empty -m "chore(stage-3): Phase 4 exit — tests repaired

Pass rate: <N>/<N>
Safety-critical signatures: all 11 present
Analyze: clean
Integration test covers range-session → drill → persisted → listed."
```

---

## Phase 5: Smoke + Hardware Verification + Merge Back

### Task 5.1: Final safety-critical signature verification

- [ ] **Step 1: Run the check**

```bash
./tool/check_safety_critical.sh
```
Expected: `All 11 signatures present.`

- [ ] **Step 2: Spot-check the stopDrill guard by reading lib/state/app_state.dart around line 292 (post-refactor line may differ — grep)**

Run: `grep -n -B 2 -A 4 '_phase != DrillPhase.running && _phase != DrillPhase.arming' lib/state/app_state.dart`

Expected output shows the comment block from e7f926b explaining the fix, immediately followed by the guard.

---

### Task 5.2: Chrome preview smoke

- [ ] **Step 1: Launch**

```bash
flutter run -d chrome --release
```

- [ ] **Step 2: Confirm the web preview stub renders**

Expected: "Atriarch web preview — tactical theme only" text visible. Because `kIsWeb` branches to `_WebPreviewApp`, full features don't exercise on the web path — that's intended.

- [ ] **Step 3: Kill the process and note the outcome**

Smoke success = the build reaches the preview screen without runtime exceptions. A non-starter build fails this task.

---

### Task 5.3: Real-device smoke (iPhone 26)

If a physical device is connected:

- [ ] **Step 1: Launch**

```bash
flutter run -d 00008140-000C0D093A98801C --release   # iPhone (2)
```

- [ ] **Step 2: Exercise each gate-2 feature**

Walk through:
- Onboarding wizard (first launch).
- Pair transmitter.
- Discover targets (hear ready chime).
- Save/load a preset.
- Start a drill, fire STOP press-hold (verify 800ms hold triggers, tap does nothing).
- Open Results → Share → confirm JSON payload appears.
- Open Settings → "Replay onboarding" → confirm flag resets.
- Open Recent Drills → confirm the drill just finished appears.
- Long-press a target chip in setup → confirm actions sheet opens; rename; verify name persists after app restart.

- [ ] **Step 3: If any feature crashes, file a follow-up and return to Phase 3 or 4 as needed**

---

### Task 5.4: SQLite state verification

- [ ] **Step 1: Pull the on-device SQLite DB (macOS simulator path shown; adjust for physical device)**

```bash
DB_PATH=$(find ~/Library/Developer/CoreSimulator -name 'atriarch.db' 2>/dev/null | head -1)
echo "$DB_PATH"
```

- [ ] **Step 2: Inspect tables**

```bash
sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table';"
```

Expected: `shooters`, `drill_templates`, `sessions`, `session_events`, `session_metrics`, `target_engagements`.

- [ ] **Step 3: Confirm a drill left real rows**

```bash
sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sessions;"
sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM session_events WHERE type IN ('ACT','HIT','DONE','FIN');"
sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM drill_templates;"
```

Expected: `sessions >= 1`, `session_events >= 3` (ACT + HIT + FIN at minimum), `drill_templates >= 1` if a preset was saved.

---

### Task 5.5: Merge `feature/stage-3-integration` → `feature/system-v2`

- [ ] **Step 1: Final full test + analyze on the integration branch**

```bash
flutter test 2>&1 | tail -5
flutter analyze 2>&1 | tail -3
./tool/check_safety_critical.sh
```

All three must be clean.

- [ ] **Step 2: Switch to the main worktree (system-v2) and merge**

From `/Volumes/T7/Atriarch` (the main worktree for feature/system-v2):

```bash
git -C /Volumes/T7/Atriarch checkout feature/system-v2
git -C /Volumes/T7/Atriarch merge --no-ff feature/stage-3-integration -m "merge(stage-3): gate-2 integration

Stage 3 of Gate-1 closeout — gate-2-work (10 commits) reconciled onto
feature/system-v2's tactical + SQLite foundation.

Landed gates (memories):
- project_theme_dark_only: dark-only ship; ThemeController stripped
- project_range_session_derived: RangeSessionView over sessions table
- project_drill_template_consolidation: DrillTemplate on drill_templates

Safety-critical signatures from e7f926b: all 11 preserved (verified by
tool/check_safety_critical.sh).

Hive removed from pubspec entirely. flutter_tts + just_audio + audio_session added."
```

- [ ] **Step 3: Verify the merge**

```bash
git -C /Volumes/T7/Atriarch log --oneline -5
git -C /Volumes/T7/Atriarch status --short
cd /Volumes/T7/Atriarch && flutter test 2>&1 | tail -3 && ./tool/check_safety_critical.sh
```

- [ ] **Step 4: Clean up worktrees**

```bash
git worktree remove .worktrees/gate-2
git worktree remove .worktrees/plan-1-persistence
# Leave .worktrees/stage-3-integration until the user confirms they want it gone.
git branch -d feature/plan-1-persistence feature/stage-3-integration gate-2-work
```

(Only remove branches after confirming they're merged.)

- [ ] **Step 5: Final commit — update Stage-3 plan status to COMPLETE**

```bash
# In the main worktree:
sed -i '' 's|^> \*\*Status:\*\* Gates locked 2026-04-23.*|> **Status:** COMPLETE — merged to feature/system-v2 on YYYY-MM-DD.|' docs/superpowers/plans/2026-04-21-stage-3-gate2-integration.md
git add docs/superpowers/plans/2026-04-21-stage-3-gate2-integration.md
git commit -m "docs(plan): mark Stage-3 integration COMPLETE"
```

---

## Self-Review Checklist

After completing ALL phases:

1. **Safety-critical fixes:** 11 signatures verified via `tool/check_safety_critical.sh`. Grep one more time by hand for `_phase != DrillPhase.running && _phase != DrillPhase.arming`, `str128.toLowerCase()`, `removeListener(_onPhaseChanged)`, `removeListener(_checkDrillComplete)`, `Duration(milliseconds: 800)`, `PopScope(canPop: false)`, `Timer(const Duration(seconds: 8)`, `encodeSnap()`, `state.discoverTargets()` — 9 expected matches plus two UUID-str128 occurrences.

2. **Data layer:** `lib/data/` should be deleted entirely (`ls lib/data` returns "No such file or directory"). `grep -r 'package:hive' lib/` returns empty. `grep -r 'HiveObject\|HiveField\|HiveType' lib/` returns empty.

3. **Pubspec:** no `hive`, `hive_flutter`, `hive_generator`, `screen_brightness`. Has `flutter_tts`, `just_audio`, `audio_session`, `fake_async`.

4. **Tests:** 90/90 plan-1 tests still green. gate-2 tests rewritten or deleted. One integration test covers the cross-cutting path.

5. **Plan doc:** `docs/superpowers/plans/2026-04-21-stage-3-gate2-integration.md` has status COMPLETE.

6. **Memories:** `project_theme_dark_only`, `project_range_session_derived`, `project_drill_template_consolidation` exist; `project_auto_theme_schedule` is removed.
