# Stage 3: Integrate Gate-2 into Tactical + SQLite System-v2

> **Status:** Plan draft — ready for brainstorm/spec pass in a fresh session. Not an executable TDD task list yet.

**Date:** 2026-04-21
**Goal:** Merge `gate-2-work` (10 commits) into `feature/system-v2` (currently post-Stage-2, at `8b8e941`), reconciling gate-2's Hive-backed repositories against plan-1's SQLite, and integrating gate-2's features (onboarding wizard, walk-the-range, presets, session history, drill log, ready-audio, dark-theme toggle, user-named targets) with the tactical UI layer.

**Why this is its own workstream:** Attempted inline during the Gate-1 closeout merge orchestration on 2026-04-21 and aborted. Scope turned out to be 10 files with 34 conflict hunks + 200–400 lines of Hive→SQLite bridge code + semantic reconciliation between two independently-designed subsystems. Not a merge-conflict-resolution task — a focused 3–6 hour engineering task that deserves a plan and its own execution arc.

---

## Current State (Precondition)

**Branch:** `feature/system-v2` at `8b8e941`.

History on system-v2 (after Gate-1 closeout merges):
- Stage 1: `19d673b` — tactical-redesign merged (27 commits, tactical UI theme + widget library + screen restyles)
- Stage 2: `8b8e941` — plan-1-persistence merged (18 commits, SQLite schema + shooter profiles + session persistence)

**Test baseline:** 90/90 pass, `flutter analyze` clean, all 6 safety-critical fixes from `e7f926b` verified.

**Memory anchors:**
- `project_persistence_decision.md` — SQLite wins for domain data; shared_preferences stays for UI settings.
- `project_safety_critical_fixes.md` — six non-negotiable fixes that must survive any refactor.
- `feedback_widget_tests_no_ffi_sqflite.md` — widget tests cannot use `sqflite_common_ffi`; use fake repos.
- `project_analytics_metrics_definition.md` — metrics clock from ACT events, not drill start.

---

## What Gate-2 Brings (10 commits)

Listed newest → oldest as they appear on `gate-2-work`:

| Commit | Feature | Primary files |
|---|---|---|
| `8331ece` | First-run onboarding wizard (#19) | `lib/screens/onboarding/*.dart`, AppState `_onboardingComplete` flag |
| `44ad86a` | Walk-the-Range + press-and-hold identify (#20) | AppState `TtsPort` + walk-range flow, `lib/widgets/target_actions_sheet.dart` |
| `dc5b0b3` | Session history + drill log + share sheet (#16+#17+#18) | `lib/screens/recent_drills_screen.dart`, `lib/data/session_repository.dart`, `lib/data/drill_log_repository.dart`, `lib/util/drill_log_codec.dart`, `lib/widgets/drill_share_sheet.dart`, `lib/widgets/drill_result_image.dart` |
| `3d0748e` | Ready-audio chime on discovery-complete (#15) | `lib/services/audio_service.dart`, AppState `_readyChimePlayedForCurrentCycle`, `assets/sounds/ready.mp3` |
| `1b94a93` | Drill presets + preset row on Program Setup (#14) | `lib/util/preset_store.dart`, `lib/widgets/preset_row.dart`, `lib/data/drill_preset.dart` (+ `.g.dart`), program_a/b_setup touches |
| `2babcf6` | User-named targets + long-press actions sheet (#13) | `lib/util/target_name_resolver.dart`, `lib/widgets/target_actions_sheet.dart`, PreferencesRepository name storage |
| `5a70152` | Auto-theme = time schedule (drop light_sensor) (#12) | `lib/theme/theme_controller.dart`, time-based auto-theme |
| `c47a57c` | Dark theme + ambient-light auto-toggle + Settings scaffold (#12) | `lib/screens/settings_screen.dart`, ThemeController |
| `56a5e62` | Tighten repository API surface after code review (#11) | Refinement commit |
| `1c7387a` | Hive + PreferencesRepository/SessionRepository/DrillLogRepository (#11) | `lib/data/hive_bootstrap.dart`, PreferencesRepository, SessionRepository (Hive), DrillLogRepository (Hive), InMemory variants for tests |

---

## Reconciliation Strategy — per Subsystem

### 1. Hive Persistence Layer → SQLite

**Key insight:** gate-2's `SessionRepository` and plan-1's `SessionRepository` share a name but are semantically different:
- **Gate-2 `SessionRepository`** (in `lib/data/`) = rolling *range-session* aggregator. Owns an 8-hour auto-clear window. Methods: `beginSessionIfNeeded()`, `appendDrill(SessionSummary)`, `clearSession()`. A range-session = "one visit to the range, many drills in it".
- **Plan-1 `SessionRepository`** (in `lib/repositories/`) = per-drill persistence. Methods: `insert(SessionRecord)`, `appendEvents()`, `closeSession()`, `findOrphanSessions()`. A session = "one fired drill, full event log".

**Resolution:** Treat these as different concepts. Rename gate-2's to `RangeSessionRepository` (or `DrillSessionSummaryRepository`). Both coexist: plan-1 owns per-drill persistence, gate-2's renamed repo owns range-visit aggregation.

**`DrillLogRepository` (gate-2):** stores per-drill JSON blobs. Redundant with plan-1's raw `session_events` table. **Delete DrillLogRepository.** Migrate callers (`drill_share_sheet.dart`, `drill_result_image.dart`, `recent_drills_screen.dart`, `util/drill_log_codec.dart`) to read events from plan-1's SQLite `session_events` table via `SessionRepository.getEventsFor(sessionId)` (a new read-only method to add).

**`PreferencesRepository` (gate-2):** mixed bag:
- `getSetting<T>` / `setSetting<T>` / `removeSetting` → stay on shared_preferences (UI settings per Gate-1 decision).
- `getDefaultPresetId` / `setDefaultPresetId` → stay on shared_preferences.
- `getTargetNames` / `setTargetName` → stay on shared_preferences (small, UI-adjacent).
- `getRemovedTargetIds` / `setRemovedTargetIds` → stay on shared_preferences.
- `listPresets` / `getPreset` / `savePreset` / `deletePreset` → **migrate to SQLite** via plan-1's `drill_templates` table (schema exists; populate it). DrillPreset model aligns closely with the `drill_templates` row shape.

This means `PreferencesRepository` stays as a class but its Hive box for presets is replaced by SQLite-backed `DrillTemplateRepository` (new, schema already exists in plan-1). The class becomes a thin wrapper over both shared_preferences + SQLite.

**`SessionSummary` model (gate-2):** currently `extends HiveObject` with a manual `TypeAdapter`. Convert to a plain immutable dataclass (like `SessionRecord`) with `toMap`/`fromMap` for the new `RangeSessionRepository` SQLite table (or just keep summaries in-memory since they auto-clear after 8h anyway — could be ephemeral, not persisted at all).

**Hive `.g.dart` files to delete:**
- `lib/data/drill_preset.g.dart`
- `lib/models/drill_config.g.dart`
- `lib/models/target_group.g.dart`
- Any manual Hive adapters in `session_summary.dart` (keep the model, drop the adapter).

**New SQLite table needed (if we persist range-sessions):**
```sql
CREATE TABLE range_sessions (
  id TEXT PRIMARY KEY,
  started_at INTEGER NOT NULL,
  cleared_at INTEGER
);
-- session_summaries belongs_to range_sessions; but given 8h auto-clear,
-- in-memory-only may be simpler. Decide during brainstorm.
```

---

### 2. Theme — tactical dark + gate-2 ThemeController

**Tactical's contribution** (already on system-v2): dark theme by default, Space Grotesk font, zero radius, tactical color tokens (`statusLive`, `statusOffline`, etc.).

**Gate-2's contribution:** `ThemeController` supporting (a) user toggle light/dark/auto, (b) auto mode = 06–18 time schedule. Per `project_auto_theme_schedule.md`, the time-schedule approach was CEO-approved.

**Resolution:**
- Keep tactical's color/type tokens and widget styling as the visual language.
- Wire gate-2's `ThemeController` as the ACTIVE theme-mode manager.
- `main.dart`'s `MaterialApp.themeMode` binds to `ThemeController.mode`.
- Dark-mode build stays tactical-dark. Light-mode build (needed because ThemeController allows user to pick light) requires producing a `buildAtriarchLightTheme()` that uses the tactical token palette with inverted surfaces — TACTICAL team didn't build this because they shipped dark-only. Either (a) build a tactical-light variant, or (b) lock the app to dark-only and neuter ThemeController's light/auto options.

**Decision needed from Jeremy:** ship dark-only (strip gate-2's theme toggle) or invest in building a tactical-light theme? Default recommendation: **dark-only for now**, defer light theme to a dedicated UI task. This means gate-2's Settings screen loses the theme toggle; auto-theme is silently ignored.

**Drill-context active flag** (gate-2's ThemeController tracks "is setup/drill screen active" for some reason — likely to suppress auto-theme during a drill). Preserve this if the light-theme path is kept; drop if dark-only.

---

### 3. AppState Integration

Gate-2 expanded AppState substantially. The merged shape needs to preserve plan-1's DI (`_sessions`, `_shooterState`, `_batcher`, `_activeDbSessionId`, `_iterationsCompleted`, `_pendingClose`) AND gate-2's additions:

**From gate-2 (keep):**
- `PreferencesRepository preferences` — now thin wrapper (shared_preferences + SQLite templates).
- `AudioService audio` — for ready chime.
- `TtsPort tts` — for walk-the-range.
- `_readyChimePlayedForCurrentCycle` + `_discoveryDoneSeenForCurrentCycle` state.
- `_onboardingComplete` flag + hydrate.
- `_targetNames` + `setTargetName` + `_removedTargetIds` + `showRemoved` toggle.
- `TargetNameResolver` accessor.

**From gate-2 (migrate):**
- `sessions` field (gate-2's Hive-backed SessionRepository) → replace with `rangeSessions: RangeSessionRepository` (renamed, SQLite-backed or in-memory).
- `drillLogs` field → **delete** (replaced by plan-1's SessionRepository.getEventsFor).

**Coexisting fields:**
- Plan-1's `_sessions` (`SessionRepository` for per-drill) + `rangeSessions` (gate-2's range-session concept, renamed). Both non-null, used for different purposes.

**Lifecycle hooks — merged:**
- `startDrill` — plan-1 inserts SessionRecord + starts EventBatcher + BLE write (with try/catch per safety-fix context); gate-2 calls `rangeSessions.beginSessionIfNeeded()` + arms audio-chime state + feeds onboarding if in first-run.
- Drill-end paths (FIN, StopAck, timeout, force-finish, SnapReply-not-running) — all five call `unawaited(_closeActiveDbSession(...))` (plan-1) AND `rangeSessions.appendDrill(summary)` (gate-2).
- `discoverTargets` — gate-2 resets chime-cycle state, plan-1 untouched.

**Safety-critical fixes must survive AGAIN:**
- STOP-flood guard at `stopDrill` entry
- SNAP reconcile on reconnect + 8s scan timeout
- Nav listener detach (in screens, not AppState, but verify during screen integration)

---

### 4. Screens — tactical + gate-2 features

Every conflicted screen needs a 3-way reconciliation (tactical's restyle + gate-2's features + plan-1's ShooterChip where applicable).

**`home_screen.dart`:** tactical restyled; gate-2 added navigation to Settings + Recent Drills + Walk-the-Range entry. Keep tactical styling; wrap gate-2's nav entries as `TacticalPrimaryButton` or `TacticalCard` tiles. Port the Walk-the-Range entry button to tactical language.

**`program_a_setup_screen.dart` / `program_b_setup_screen.dart`:** three-way conflict:
- tactical: TacticalScaffold, TacticalMinMaxCard, GroupNodeCard, tactical imports
- plan-1: ShooterChip in body header (moved from AppBar after test revealed overflow)
- gate-2: PresetRow above the form, PresetStore wiring in initState/dispose, target actions sheet (long-press group cards)

All three must coexist. Approximate layout: `ListView([ShooterChip, _header, PresetRow, ...tactical-sections])`. Long-press on GroupNodeCard triggers gate-2's target_actions_sheet. Presets load into the same controllers tactical restyled.

**`drill_running_screen.dart`:** tactical HUD layout + gate-2 drill-log event capture. Tactical already has event capture via AppState; drill-log codec encoding happens in appendDrill (AppState). No UI conflict on the drill-running screen itself beyond style.

**`results_screen.dart`:** tactical dossier layout + gate-2 share sheet button. Keep tactical dossier; replace gate-2's classic AppBar actions with a tactical action — or wire "Share" as the primary footer button.

**`settings_screen.dart` (NEW from gate-2):** needs tactical retrofit. Build as `TacticalScaffold` with tactical section cards for each toggle row.

**`recent_drills_screen.dart` (NEW from gate-2):** same — tactical retrofit. List rows styled as tactical cards.

**`lib/screens/onboarding/*.dart` (NEW from gate-2):** 5 step files (welcome, pair_transmitter, discover_targets, first_drill, onboarding_flow). Retrofit to tactical shell. Each step uses `TacticalScaffold` with a single-purpose body.

---

### 5. Widget Tests

Gate-2 added widget tests that will need the same fake-repo treatment we applied in Stage 2. In particular, any test that mounts a screen now depending on PreferencesRepository, AudioService, or TtsPort needs injected fakes. Build on `test/test_helpers/fake_shooter_repo.dart` pattern; add `FakePreferencesRepository`, `FakeAudioService`, `RecordingTtsPort` (gate-2 already ships this — reuse).

**Known widget test pitfall:** gate-2 likely has tests that hit `DatabaseHelper.openForTesting()` or `hive_bootstrap.dart`. Any that pump widgets against them MUST migrate to fake repos.

---

## Execution Phases

Decompose the merge into **5 phases** landed as separate commits so each step is reviewable + revertible. Each phase ends with `flutter test` + `flutter analyze` green.

### Phase 1: Prep — fork a branch, delete stash nuisances
- Create `feature/stage-3-integration` off `feature/system-v2@8b8e941`
- Clear macOS `._*` sidecars
- Commit `macos/Flutter/GeneratedPluginRegistrant.swift` as a prep commit (it's auto-regenerated but committing it gives a clean working tree for the rest of the work).

### Phase 2: Gate-2 non-UI infrastructure (mechanical merge + rename)
- Merge gate-2-work but resolve NON-UI conflicts only (app_state.dart data fields, pubspec, theme)
- Rename gate-2's `SessionRepository` (in `lib/data/`) → `RangeSessionRepository` to avoid clash with plan-1's. Update all call sites.
- Delete `DrillLogRepository` + its usages (replace with plan-1's event stream).
- Decide theme-scope (dark-only vs build tactical-light). If dark-only: strip ThemeController's light/auto mode.
- Delete Hive `.g.dart` files + Hive imports from models that don't need them anymore. `SessionSummary` becomes a plain dataclass.
- Migrate `DrillPreset` storage from Hive box to plan-1's `drill_templates` SQLite table via a new `DrillTemplateRepository`. Update `PreferencesRepository.savePreset/listPresets/...` to delegate.

**Exit:** `flutter test` passes (may require fixing gate-2's repository tests against new SQLite bridge); `flutter analyze` clean.

### Phase 3: Screen conflicts resolved (tactical retrofit)
- Resolve `home_screen`, `program_a/b_setup_screen`, `drill_running_screen`, `results_screen` conflicts. Preserve tactical layout; wire gate-2 features (PresetRow, TargetActionsSheet, ShareSheet) into the tactical language.
- Retrofit new gate-2 screens (`settings_screen`, `recent_drills_screen`, onboarding steps) to TacticalScaffold.
- Verify all 6 safety-critical signatures still present.

**Exit:** Full test suite green. App builds and launches (Chrome preview verifies without real hardware).

### Phase 4: Test coverage repair
- Any gate-2 widget tests that used `DatabaseHelper.openForTesting()` or Hive bootstrap → rewrite with fake repos (`FakePreferencesRepository`, `FakeAudioService`, `RecordingTtsPort` already exists).
- Any gate-2 test that depended on DrillLogRepository → rewrite against new event-reading API.
- Add one integration test covering the cross-cutting "range session → drill → persisted → listed in recent-drills" path.

**Exit:** ≥95% of gate-2's tests pass (some legacy tests may be obsolete and deleted with intent).

### Phase 5: Smoke + hardware verification
- Manually smoke-test the app (Chrome preview + one real-device run if possible) touching each feature: onboarding wizard, walk-the-range, presets, drill history, share sheet, ready chime, settings toggles, user-named targets.
- Verify database state on disk after drills (use `sqlite3` CLI against the on-device DB or a dev dump).
- Run through the 6 safety-critical fixes one more time on the merged branch.

**Exit:** Green across the board. Merge `feature/stage-3-integration` back to `feature/system-v2` as the third and final Gate-1 closeout merge.

---

## Known Risks / Open Questions (for brainstorm session)

1. **Light theme: build or cut?** Dark-only is cheaper but loses a gate-2 feature. Full tactical-light is a separate UI sprint.
2. **Range-session persistence: SQLite table or in-memory only?** Gate-2 clears after 8h anyway. In-memory is cheaper and avoids schema churn but loses app-restart survival (minor UX loss).
3. **DrillTemplate vs DrillPreset: merge models or keep both?** Gate-2 has `DrillPreset`, plan-1's schema has `drill_templates`. They represent the same concept. Recommend: single `DrillPreset` class, SQLite-backed via `drill_templates` table.
4. **Onboarding wizard styling:** gate-2 built it pre-tactical. Retrofit effort is ~5 step files × ~30 min each. Acceptable.
5. **Walk-the-Range TTS plugin:** `flutter_tts` pub dep needs to come in via gate-2's pubspec merge. Verify it builds on iOS 26. (Possible plugin init deadlock if it needs platform-channel init before `runApp`; `main.dart` already calls `WidgetsFlutterBinding.ensureInitialized()` which should be sufficient.)
6. **Ready-audio asset:** `assets/sounds/ready.mp3` gets added via the merge. Confirm `pubspec.yaml` asset section includes it.
7. **Hive artifact cleanup:** Once Hive is removed, `pubspec.yaml` loses `hive`, `hive_flutter`, `hive_generator`, `build_runner` (if used solely for Hive). Don't miss these or builds will drag unused heavyweight deps.
8. **Gate-2's pre-existing session-history tests:** if they were written against Hive's synchronous-ish behavior, some async-timing adjustments may be needed against SQLite's explicit `await`.

---

## Success Criteria

1. `feature/system-v2` is at a merge commit representing Stage 3, with all 10 gate-2 commits + bridge/retrofit work landed.
2. Full test suite passes locally (≥95% of combined pre-merge suites; zero tests left in a broken/skipped state).
3. `flutter analyze` reports no issues.
4. All 6 safety-critical fixes from `e7f926b` verified intact (same grep sweep as Stage 1 & 2).
5. App launches on Chrome preview and on one real iOS device; onboarding wizard, walk-the-range, preset save/load, drill history with share sheet, and ready chime all exercise their happy path.
6. `sqflite` DB contains expected rows after a test drill: `shooters`, `sessions`, `session_events`, `drill_templates`.
7. `feature/plan-1-persistence` branch can be deleted (already merged); `gate-2-work` branch can be deleted (already merged); `feature/tactical-redesign` already deleted in Stage 1.
8. Worktrees at `.worktrees/gate-2` and `.worktrees/plan-1-persistence` can be removed with `git worktree remove`.

---

## Recommended Next Action

**Start a fresh Claude session tomorrow.** Reference this doc. Run `superpowers:brainstorming` over the open questions above to lock in decisions (especially theme-scope and range-session persistence), then `superpowers:writing-plans` to generate a concrete TDD task breakdown for Phases 2-5. Execute via `superpowers:subagent-driven-development` in a dedicated worktree off `feature/system-v2@8b8e941`.

Preserve this plan file — it's the starting pin for the brainstorm.
