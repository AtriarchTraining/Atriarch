# Atriarch Analytics & Deep Insights — Design

**Date:** 2026-04-20
**Status:** Approved design, ready for implementation planning
**Scope:** V1 ship of full deep-analytics suite — persistence, shooter profiles, per-session results, history, trends, deep correlations, drill templates, export.

---

## Summary

Turn every drill fired on an Atriarch tablet into a durable training record with per-session metrics, per-shooter longitudinal trends, and deep-analytics correlations (reaction-vs-delay, weak-side, fatigue, warmup). Design the data model and export format now to seamlessly migrate to the sister "Range Buddy" app later, so shooters who train on a coach's tablet can claim their history when they onboard to Range Buddy.

**Core insight driving the design:** all metrics clock from target activation (`ACT`) events, not from drill start. This makes every metric independent of drill randomization (random start/inter-target delays) and turns those random delays from a confound into an *independent variable* for deep analytics ("does your reaction slow when the delay is longer?").

---

## 1. Architecture & Data Flow

```
BLE events (ACT/HIT/DONE/NS/LATE/FIN)
        │
        ▼
  DrillSession (in-memory, during drill)  ── unchanged from today
        │
        ▼ (on drill end)
  SessionWriter ──► SQLite (sessions + events + metrics tables)
                         │
                         ▼
                  MetricsEngine (pure functions)
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
     Results         History         Deep
     Screen          + Trends        Analytics
   (one session)   (per shooter)   (correlations)
```

**Key choices:**

- **Raw event log is the source of truth.** Every `ACT`/`HIT`/`DONE`/`NS`/`LATE`/`FIN` timestamp is persisted verbatim. Metrics are *derived* — computed by pure functions that take a session's events and return a metrics object. Any new metric added in the future is computable retroactively over every session ever fired.
- **MetricsEngine is pure Dart, no BLE/DB deps.** Enables comprehensive unit tests against synthetic event sequences with no hardware.
- **SQLite via `sqflite`** (Flutter standard). One DB file per tablet, survives app restarts, handles tens of thousands of sessions.
- **Compute + cache strategy.** At drill end, MetricsEngine runs once, results stored in `session_metrics` + `target_engagements`. History/Trends queries read the cache. Deep-analytics recomputes on-demand (joins across sessions). A `metrics_version` constant enables one-shot recomputes when engine math changes.

---

## 2. Data Model

```sql
-- PROFILES
shooters(
  id TEXT PK,                    -- UUID, Range Buddy-compatible
  display_name TEXT NOT NULL,
  contact_email TEXT NULL,       -- optional, for future data claim via Range Buddy
  contact_phone TEXT NULL,       -- E.164 format ("+14155551234"); optional
  created_at INTEGER NOT NULL,   -- epoch ms
  range_buddy_user_id TEXT NULL  -- populated when claim succeeds
)

-- CONFIG
drill_templates(
  id TEXT PK,                    -- UUID
  shooter_id TEXT NULL REFERENCES shooters(id),  -- NULL = shared across shooters
  name TEXT NOT NULL,
  program_type TEXT NOT NULL,    -- 'A' | 'B'
  config_json TEXT NOT NULL,     -- serialized DrillConfig
  config_hash TEXT NOT NULL,     -- sha256 of canonicalized config, for retroactive matching
  created_at INTEGER NOT NULL
)

-- RAW (source of truth)
sessions(
  id TEXT PK,                    -- UUID
  shooter_id TEXT NOT NULL REFERENCES shooters(id),
  template_id TEXT NULL REFERENCES drill_templates(id),  -- back-filled if hash matches
  program_type TEXT NOT NULL,
  config_json TEXT NOT NULL,     -- frozen snapshot at drill start
  config_hash TEXT NOT NULL,
  started_at INTEGER NOT NULL,   -- wall-clock epoch ms
  ended_at INTEGER NULL,
  finished_normally INTEGER NOT NULL DEFAULT 0,
  iterations_completed INTEGER NOT NULL DEFAULT 0
)

session_events(                  -- verbatim BLE event log
  id INTEGER PK AUTOINCREMENT,
  session_id TEXT NOT NULL REFERENCES sessions(id),
  sequence INTEGER NOT NULL,     -- tablet-assigned on receipt
  type TEXT NOT NULL,            -- ACT|HIT|DONE|NS|LATE|FIN|ERROR
  target_id INTEGER NULL,
  hit_number INTEGER NULL,
  required_hits INTEGER NULL,
  total_time_ms INTEGER NULL,
  error_detail TEXT NULL,
  timestamp INTEGER NOT NULL     -- wall-clock epoch ms on receipt
)

-- DERIVED (cache, fully regeneratable from session_events)
session_metrics(
  session_id TEXT PK REFERENCES sessions(id),
  draw_ms INTEGER NULL,
  total_duration_ms INTEGER NULL,
  total_rounds_fired INTEGER NOT NULL DEFAULT 0,
  no_shoot_count INTEGER NOT NULL DEFAULT 0,
  late_hit_count INTEGER NOT NULL DEFAULT 0,
  avg_reaction_ms INTEGER NULL,
  median_reaction_ms INTEGER NULL,
  avg_split_ms INTEGER NULL,
  avg_transition_ms INTEGER NULL,
  stddev_reaction_ms INTEGER NULL,
  data_quality_warning INTEGER NOT NULL DEFAULT 0,  -- 0/1 flag
  metrics_version INTEGER NOT NULL
)

target_engagements(              -- per-target row, deep-analytics join table
  id INTEGER PK AUTOINCREMENT,
  session_id TEXT NOT NULL REFERENCES sessions(id),
  target_id INTEGER NOT NULL,
  engagement_index INTEGER NOT NULL,  -- nth engagement of this target in session
  activated_at INTEGER NOT NULL,
  preceding_delay_ms INTEGER NOT NULL,  -- randomized delay the tablet scheduled before this ACT.
                                         -- For the first engagement of a drill: the start-delay window
                                         -- (drawn from config.startMin/startMax).
                                         -- For subsequent engagements: the inter-target delay
                                         -- (drawn from config.delayMin/delayMax).
                                         -- This is the independent variable for deep-analytics correlations.
  reaction_ms INTEGER NULL,      -- ACT → first HIT (null if never hit)
  hits_landed INTEGER NOT NULL DEFAULT 0,
  required_hits INTEGER NOT NULL,
  engagement_time_ms INTEGER NULL,  -- ACT → DONE (null if incomplete)
  was_no_shoot INTEGER NOT NULL DEFAULT 0,
  had_late_hit INTEGER NOT NULL DEFAULT 0
)
```

**Indexes:**
- `sessions(shooter_id, started_at DESC)` — history list pagination
- `session_events(session_id, sequence)` — event replay ordering
- `target_engagements(session_id)` — per-session timeline queries
- `target_engagements(session_id, target_id)` — weak-side analysis

**Key design decisions:**

- **UUIDs for shooters / sessions / templates.** Range Buddy migration becomes additive, no id remapping. Cost ~36 bytes/key vs 8-byte int; negligible at this scale.
- **`config_hash` on sessions and templates.** Enables retroactive template linkage — a user can fire 20 ad-hoc drills, save one as a template, and the hash join back-fills every prior session with matching config as that template.
- **`target_engagements` is the unsung hero.** `preceding_delay_ms` captured at write time (the tablet scheduled the delay, knows it). All deep-analytics correlations become straightforward SQL joins.
- **`metrics_version` column.** When engine math changes, bump the constant in code; a background sweep recomputes stale rows from raw events. No destructive migrations.

---

## 3. Metric Definitions

**All metrics clock from `ACT` events, not drill start** — making them independent of drill randomization.

### Core session metrics (stored in `session_metrics`)

| Metric | Formula | Notes |
|---|---|---|
| `draw_ms` | `first_HIT.ts − first_ACT.ts` | Null if drill aborted before first hit |
| `reaction_ms` (per engagement) | `first_HIT_on_target.ts − ACT(target).ts` | Null if target never hit |
| `split_ms` (list per engagement) | `HIT_n.ts − HIT_{n-1}.ts` on same target | Aggregated avg/median/min/max |
| `transition_ms` | = `reaction_ms` of a non-first engagement | Display label for reaction when it follows another target. `avg_transition_ms` in session_metrics = avg of reaction_ms across all engagements *except the first* (since the first has no prior target to transition from). |
| `engagement_time_ms` | `DONE.total_time_ms` (firmware-reported) | ACT → DONE |
| `rounds_fired` | `count(HIT) + count(NS)` | NS = round that landed on wrong target |
| `no_shoot_count` | `count(NS)` events | Per-target breakdown stored on engagements |
| `late_hit_count` | `count(LATE)` events | Firmware decides "late" |
| `hit_accuracy` | `hits_landed / required_hits` per engagement | Meaningful when `required_hits > 1` |
| `stddev_reaction_ms` | stddev of per-engagement reactions in session | Lower = sharper |

### Deep-analytics metrics (computed on-demand via SQL over `target_engagements`)

- **Reaction vs. preceding delay correlation** — per shooter, date-range-filterable. Scatter `(delay_ms, reaction_ms)` + Pearson r. Headline insight: *"Your reaction slows by ~120ms when delay exceeds 2s — classic anticipation decay."*
- **Weak-side analysis** — group engagements by `target_id`, show avg `reaction_ms` per target. Surfaces physical-layout / body-mechanics bias.
- **Fatigue curves (intra-session)** — `reaction_ms` vs `engagement_index` within a session. Rising slope = fatigue.
- **Warmup curves (inter-session)** — first-iteration reaction averaged across sessions vs last-iteration. Quantifies warmup duration.
- **Consistency trend** — stddev and coefficient of variation of reaction per session, trended over time. Often more meaningful than trending the mean.
- **No-shoot rate trend** — `count(NS) / total_engagements` over time. Training signal for trigger discipline.

### Aggregate trends (per shooter, across sessions)

Rolling 7d / 30d / 90d aggregates of: avg draw, median reaction, median split, no-shoot rate, consistency. Drive History/Trends charts.

### Edge cases handled

- Session aborted mid-drill → metrics computed on partial data, `finished_normally=0`, excluded from trend aggregates by default (toggle to include).
- Target activated but never hit → `reaction_ms = null`, engagement row still stored (avoids silently dropping failures and biasing trends toward successes).
- Shooter forgot to pick a profile → drill assigned to reserved "Unassigned" shooter; post-drill prompt offers reassignment.

---

## 4. Views / UX

**Navigation:** add bottom nav / sidebar to app root — **Train | History | Analytics | Settings**. Home screen stays the Train entry point. On tablet landscape, History and Analytics use master-detail splits.

### 4.1 Shooter Picker (new, modal)
- **When it opens:**
  - Automatically on first-ever drill start (no shooters exist yet, or none selected).
  - When the user taps the "Firing as: Jeremy ▾" chip on the drill setup screen.
  - From Settings → Shooters.
- **When it does NOT open:** on subsequent drill starts after a shooter has been selected — the last-selected shooter persists across sessions and drills start immediately with that shooter assigned. The chip in the drill setup header is the always-available escape hatch to switch.
- List of saved shooters with most-recent indicator; "+ Add shooter" row.
- **Add shooter form:** display name (required) + optional collapsible "Link for later" section with email and phone (E.164 normalized on save).
  - Helper text: *"Enter your email or phone and your training data will automatically sync when you get your own Atriarch or sign in to Range Buddy."*
  - Email/phone invalid format → save as-is, show inline warning, don't block.
- Duplicate shooter names allowed; picker disambiguates with "last fired" date.

### 4.2 Results Screen (enhanced, existing `results_screen.dart`)
- Keeps current summary.
- Adds full metric grid (draw, avg/median reaction, avg/median split, transitions, rounds, no-shoots, late hits, consistency).
- Adds per-target engagement timeline — horizontal swim-lane chart, one row per target, marks for ACT + each HIT, reaction/split times labeled inline.
- Footer actions: "Save as template", "Export session", "Back to Train".

### 4.3 History (new)
- Per-shooter session list, most-recent first, paginated (`LIMIT 50` infinite scroll).
- Each row: date, drill name (template or "Program A ad-hoc"), draw time, hit %, no-shoots badge, incomplete badge if aborted.
- Tap row → Session Detail (same layout as Results Screen, loaded from DB).
- Filter bar: template picker, date range, "exclude aborted" toggle.
- Empty state: "Fire your first drill to start building history."

### 4.4 Analytics (new)
- Scrollable card feed. Each card = one insight.
- **Trend cards** (always visible once data exists): draw over 30d, median reaction, no-shoot rate, consistency. Each expands to full-screen chart with 7d/30d/90d/all toggle.
- **Correlation cards** (empty-state message "Fire N more sessions to unlock" until thresholds met): reaction vs preceding delay (scatter + fit line + plain-English summary), weak-side bars, warmup curve, intra-session fatigue.
- **Template cards**: templates with 3+ runs show apples-to-apples trending on that specific drill.

### 4.5 Drill Templates (under Settings)
- List of saved templates. Row actions: rename, delete, "Fire this drill".
- Save path: Results footer button or Setup "Save as template" action.
- Opening a template shows count of retroactively matched prior sessions.

### 4.6 Settings — Shooters section
- Each shooter row: display name, session count, date range, last-fired.
- Actions per shooter: Edit (name, email, phone), **Forget this shooter** (destructive — confirmation dialog lists session count + date range; cascades to `sessions` / `session_events` / `session_metrics` / `target_engagements`; templates owned by that shooter either migrate to shared or delete per user choice).

### 4.7 Export (embedded action)
- From Results: export one session.
- From History: multi-select → export CSV or JSON.
- **CSV export excludes PII by default** — no email/phone, just event stream + metrics. Suitable for sharing or Excel analysis.
- **JSON export includes PII only on explicit user opt-in** — for Range Buddy migration. Dialog: "Include contact info in export? (Only needed if migrating to Range Buddy.)"
- Uses `share_plus` platform share sheet.

### Dependencies

- **Charts:** `fl_chart` (MIT, pure Dart, small). Covers line, scatter, bar.
- **Sharing:** `share_plus`.
- **SQLite:** `sqflite`.
- **UUIDs:** `uuid`.

---

## 5. Storage & Migration

**DB file:** `getApplicationDocumentsDirectory()/atriarch.db`, managed by `sqflite`.

### Write path per drill

1. Drill starts → `INSERT INTO sessions` with config snapshot + `config_hash`, `started_at = now()`.
2. BLE events stream in → batched writes every ~500ms to `session_events` (avoids per-event fsync stutter). On drill end / app background, pending batch flushes immediately.
3. `FIN` event arrives → `UPDATE sessions SET ended_at, finished_normally=1`.
4. MetricsEngine runs on just-closed session → `INSERT INTO session_metrics` + bulk `INSERT INTO target_engagements`.
5. Template back-fill: if any `drill_templates.config_hash` matches, `UPDATE sessions SET template_id`.

### Retention

- Keep forever locally. SQLite handles tens of thousands of sessions.
- Settings action: "Delete sessions older than N days" for users who want cleanup.
- Per-shooter "Forget this shooter" performs cascade delete.

### Schema versioning

- `sqflite`'s `onCreate` (v0 → current) and `onUpgrade(oldV, newV)` hooks.
- `DATABASE_VERSION` constant ladder in code, each step commented with migration rationale.
- Migrations are additive when possible (add column, add table); never destroy raw events.
- **Metric formula changes** bump `METRICS_VERSION` constant (separate from DB version). On app launch, find rows where `session_metrics.metrics_version < CURRENT`, recompute from raw events in an isolate, throttled to 20 sessions/sec.

### Range Buddy export format (JSON)

```json
{
  "schema_version": 1,
  "exported_at": "2026-04-20T19:05:00Z",
  "shooter": {
    "local_id": "uuid-...",
    "display_name": "Jeremy",
    "contact_email": "...",
    "contact_phone": "..."
  },
  "sessions": [
    {
      "id": "uuid-...",
      "program_type": "A",
      "config": { "...full DrillConfig..." },
      "config_hash": "sha256-...",
      "started_at": 1745176800000,
      "ended_at": 1745177040000,
      "finished_normally": true,
      "events": [
        {"seq": 0, "type": "ACT", "target_id": 1, "ts": 1745176802100},
        {"seq": 1, "type": "HIT", "target_id": 1, "hit_number": 1, "required_hits": 2, "ts": 1745176802850}
      ],
      "metrics": { "...session_metrics row..." },
      "engagements": [ "...target_engagements rows..." ]
    }
  ]
}
```

When Range Buddy integration ships, the server accepts this payload verbatim — no schema rewrite.

### CSV export (one session, shareable, no PII)

```
seq, event_type, target_id, hit_number, required_hits, ts_epoch_ms, relative_ms
0, ACT, 1, , , 1745176802100, 0
1, HIT, 1, 1, 2, 1745176802850, 750
```

Plus a companion `_metrics.csv` with the flattened session_metrics row.

### Claim flow (future, Range Buddy side — designed now)

1. Shooter signs up to Range Buddy with email/phone.
2. Tablet comes online with Range Buddy auth → scans local `shooters` rows for unclaimed matches: `range_buddy_user_id IS NULL AND (contact_email = ? OR contact_phone = ?)`.
3. Match → tablet uploads that shooter's sessions/events/engagements, stamps `range_buddy_user_id` to prevent re-upload.
4. No match → data stays tablet-local indefinitely.

### Backup/restore (optional V1)

Single "Export all data" action: zip the whole `atriarch.db` + write versioned archive the user can email/save. Import reverses. Cheap once export is built.

---

## 6. Error Handling & Edge Cases

### Drill interruption

- **BLE disconnect mid-drill** → session stays in DB with `ended_at=NULL`. Next app launch, a startup sweep closes orphan sessions (`finished_normally=0`, `ended_at` = last event ts), runs MetricsEngine over partial events, flags them with an "incomplete" badge in History. Excluded from trend aggregates by default.
- **User hits STOP** → `STOP_ACK` closes session cleanly with `finished_normally=0`.
- **App killed / backgrounded** → same orphan-recovery path on relaunch.

### Clock & timing guarantees

- Session records **both** wall-clock `started_at` (for display) and a monotonic `Stopwatch` baseline (for event deltas).
- Event `timestamp` columns store wall-clock epoch ms, but metric computations (draw/reaction/split/transition) use deltas from session baseline — immune to NTP jumps mid-drill.
- Tablet assigns `sequence` on receipt (BLE protocol has no sequence numbers).

### Data integrity

- **MetricsEngine never throws** — pure function, returns nullable fields when data is missing. UI shows "—" for null metrics.
- **Malformed sequences** (zero ACTs, HIT before ACT, etc.) produce a valid row with mostly-null metrics and `data_quality_warning=1`. History shows amber icon.
- **Duplicate shooter names** allowed; picker disambiguates with "last fired" date.
- **Invalid email/phone** saved as-is, inline warning, doesn't block.
- **Stale `metrics_version`** recomputes in isolate on app launch, throttled; screens show cached value with "updating" indicator during recompute of the viewed session.

### Performance

- History pagination: `LIMIT 50 OFFSET N`, infinite scroll.
- Trends queries pre-aggregate in SQL (`GROUP BY date_bucket`), not in Dart.
- Event writes batched every ~500ms during drill, immediate flush on end.

### Deletion paths

- **Forget this shooter** — confirmation lists session count + date range; cascades to sessions, events, metrics, engagements. Templates owned by shooter: migrate to shared or delete per user choice.
- **Individual session delete** from History → cascades. Irreversible.

### Unassigned drills

- Drill fired with no shooter → reserved "Unassigned" shooter (fixed UUID constant). Post-drill prompt: "Assign this drill to a shooter?" → picker → `UPDATE sessions SET shooter_id`. If dismissed, drill stays under Unassigned; can be reassigned later from Results or History.

### Deliberately NOT handled in V1

- Multi-tablet sync conflicts (Range Buddy territory).
- Sessions spanning midnight / timezone changes mid-session (drills are <10 min).
- Concurrent drills (architecturally single-drill; `BleService` enforces).

---

## 7. Testing Approach

Pyramid tilts heavily toward unit tests — MetricsEngine is where wrong numbers would be most harmful and is pure/fast to test exhaustively.

### Unit tests — MetricsEngine

- **Fixture library** at `test/fixtures/`: hand-authored `List<SessionEvent>` sequences covering clean drill, no-shoot mid-drill, late hit, drill aborted after N iterations, target activated but never hit, multi-hit target with tight splits, Program A 5 targets, Program B 10 iterations. Each fixture ships with an `.expected.json` of correct metric values.
- **Property-based tests** (hand-rolled generators or `glados` package): invariants that must hold for any valid sequence — `reaction_ms >= 0`, `split_ms[n] >= 0`, `rounds_fired == count(HIT) + count(NS)`, `engagement_time_ms == DONE.total_time_ms`, null-propagation when required events are missing.
- **Explicit edge cases**: empty session, single ACT with no HITs, HIT before ACT (malformed), duplicate FIN events, out-of-order events.

### Unit tests — config hashing

- Same `DrillConfig` → same hash.
- Field-order-independent (JSON key order doesn't matter).
- Meaningful field change → different hash.
- Cosmetic change (whitespace) → same hash.

### Unit tests — deep-analytics queries

- Synthetic `target_engagements` arrays → assert Pearson r within floating-point tolerance.
- Weak-side: fixture with known asymmetry → verify correct `target_id` flagged.
- Fatigue: monotonically rising reactions → positive slope detected; flat → no flag.

### Integration tests — persistence (sqflite in-memory)

- Full round-trip: ingest fixture events → write → read back → assert equality.
- Migration: load DB snapshot from prior version → run migration → assert new schema + data intact.
- Orphan recovery: write session with `ended_at=NULL` → run startup sweep → assert closed with `finished_normally=0`.
- Cascade delete: create shooter with N sessions/events/engagements → delete → assert zero rows.

### Integration tests — export round-trip

- Write session → export JSON → parse back → assert event stream + metrics equal originals.
- CSV export: header row + row count + PII-exclusion verification.

### Widget tests (light)

- Golden tests for Results, History list row, Session Detail timeline.
- Skip golden tests for charts (pixel-volatile); assert data-in, not pixels-out.

### Manual hardware end-to-end (one-time acceptance, not CI)

- Fire a known drill on real firmware. Export session JSON. Compare computed metrics vs stopwatch-measured ground truth. Save JSON as regression fixture.

### Replay utility (dev tool, doubles as regression harness)

- CLI: `dart run tool/replay_session.dart <session_id>` — loads raw events from DB, pipes through MetricsEngine, prints metrics diff vs stored cache. Useful for debugging reported shooter bugs, sanity-checking after engine changes, and building new deep-analytics features against real historical data.

### Out of scope for V1 tests

- `BleService` itself (existing, separate test surface).
- Firmware behavior (separate project, bench-tested).
- Chart rendering pixels (too brittle).

---

## Open Questions

None remaining — all resolved during brainstorming. Ready for implementation planning.

## Future Phases (explicitly deferred)

- **Range Buddy cloud sync** — uses the export format defined here; server-side ingestion + bidirectional sync.
- **Competition / leaderboards** (Approach D from brainstorm) — scored drills, sharing, rankings.
- **Multi-tablet conflict resolution** — when a shooter trains on multiple tablets, merge histories.
- **Shot-timer audio fallback** — if reactive-target limitations ever prove insufficient for some metric, consider tablet mic or target-PCB MIC header activation. Current design does NOT require this.

---

## Success Criteria

1. Every drill fires → all events persisted, all metrics computed, survives app restart.
2. A coach with 5 students on one tablet can review any student's full history in <2 taps from home.
3. A shooter who enters contact info, trains 20 sessions, then signs up for Range Buddy automatically has all 20 sessions in their Range Buddy account.
4. A shooter who fires 10+ sessions sees at least one deep-analytics insight (reaction-vs-delay correlation, weak-side, or fatigue) populated with real data.
5. MetricsEngine unit tests ≥95% branch coverage; property-based tests pass for 1000+ generated sequences.
6. Orphan recovery closes any incomplete session cleanly on next launch with no data loss of captured events.
