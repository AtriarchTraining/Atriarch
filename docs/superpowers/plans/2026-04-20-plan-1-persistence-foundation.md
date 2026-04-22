# Plan 1: Persistence Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every fired drill is persisted to a local SQLite database under a named shooter profile, survives app restarts, and recovers gracefully from interruption — with zero user-visible metrics/history UI yet (those land in Plans 2–4).

**Architecture:** Add a `sqflite` database alongside the existing in-memory `DrillSession`. Hook into `AppState`'s event handling to mirror events to `session_events` in batches. Introduce `ShooterState` (ChangeNotifier) for the current selected shooter, persisted across launches via `shared_preferences`. New Shooter Picker modal and chip widget integrate into existing Program A/B setup screens. On app startup, an orphan-recovery sweep closes any sessions left open by a prior crash.

**Tech Stack:** Dart, Flutter, `sqflite` (SQLite), `sqflite_common_ffi` (host-side tests), `uuid`, `crypto` (sha256), `provider`, `shared_preferences`.

**Reference spec:** `docs/superpowers/specs/2026-04-20-analytics-deep-insights-design.md` (sections 1, 2, 4.1, 5, 6).

**Out of scope (later plans):** MetricsEngine, Results screen enhancements, History screen, trends, deep analytics, templates, export, bottom nav.

---

## File Structure

**New files:**
- `lib/db/database_helper.dart` — sqflite singleton, `onCreate` wiring to schema SQL, DB path resolution
- `lib/db/schema.dart` — schema v1 SQL constants (tables, indexes, seed Unassigned shooter)
- `lib/models/shooter.dart` — immutable Shooter data class
- `lib/models/session_record.dart` — immutable SessionRecord data class (row in `sessions` table)
- `lib/services/contact_validator.dart` — email format validation + E.164 phone normalization
- `lib/services/config_hasher.dart` — canonical-JSON sha256 of DrillConfig
- `lib/services/event_batcher.dart` — buffers `SessionEvent`s, flushes to repo every 500ms
- `lib/services/orphan_recovery.dart` — startup sweep closes incomplete sessions
- `lib/repositories/shooter_repository.dart` — shooter CRUD
- `lib/repositories/session_repository.dart` — session + event CRUD
- `lib/state/shooter_state.dart` — `ChangeNotifier` for current shooter, persists via `shared_preferences`
- `lib/widgets/shooter_chip.dart` — "Firing as: X ▾" chip widget
- `lib/screens/shooter_picker_screen.dart` — modal picker + add-shooter form
- `lib/constants.dart` — reserved constants (Unassigned shooter UUID, DB file name, schema version)

**New tests:**
- `test/test_helpers/test_database.dart` — helper to spin up an in-memory sqflite DB for tests
- `test/db/database_helper_test.dart`
- `test/models/shooter_test.dart`
- `test/models/session_record_test.dart`
- `test/services/contact_validator_test.dart`
- `test/services/config_hasher_test.dart`
- `test/services/event_batcher_test.dart`
- `test/services/orphan_recovery_test.dart`
- `test/repositories/shooter_repository_test.dart`
- `test/repositories/session_repository_test.dart`
- `test/state/shooter_state_test.dart`
- `test/widgets/shooter_chip_test.dart`
- `test/screens/shooter_picker_screen_test.dart`
- `test/integration/drill_persistence_test.dart`

**Modified files:**
- `pubspec.yaml` — add deps
- `lib/main.dart` — initialize DB + run orphan recovery before widget tree, inject `ShooterState` provider
- `lib/state/app_state.dart` — on drill start, create session row + prime event batcher; on each incoming event, append to batcher; on drill end, close session
- `lib/screens/program_a_setup_screen.dart` — add ShooterChip to AppBar
- `lib/screens/program_b_setup_screen.dart` — add ShooterChip to AppBar

---

## Task 1: Add Dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add new dependencies to `pubspec.yaml`**

In the `dependencies:` block, add (maintain alphabetical order within the block):

```yaml
  crypto: ^3.0.3
  sqflite: ^2.3.0
  uuid: ^4.2.0
```

In the `dev_dependencies:` block, add:

```yaml
  sqflite_common_ffi: ^2.3.0
```

- [ ] **Step 2: Install**

Run: `flutter pub get`
Expected: `Got dependencies!` with no errors.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): add sqflite, uuid, crypto, sqflite_common_ffi for persistence foundation"
```

---

## Task 2: Constants file

**Files:**
- Create: `lib/constants.dart`

- [ ] **Step 1: Create the constants file**

```dart
// lib/constants.dart
//
// Project-wide constants for schema versions, reserved IDs, and DB filenames.

/// SQLite database filename on disk (under ApplicationDocumentsDirectory).
const String kDatabaseFileName = 'atriarch.db';

/// Schema version for sqflite's onUpgrade ladder. Bump when adding tables/columns.
const int kDatabaseVersion = 1;

/// MetricsEngine output version. Plan 2 will use this to detect stale cache
/// rows needing recompute. Declared here so schema knows the initial value.
const int kMetricsVersion = 1;

/// Reserved "Unassigned" shooter UUID. Seeded at DB creation. Drills fired
/// without an explicit shooter get tagged here.
const String kUnassignedShooterId = '00000000-0000-0000-0000-000000000000';

/// Reserved display name for the Unassigned shooter row.
const String kUnassignedShooterName = 'Unassigned';

/// Event-batcher flush interval during a live drill.
const Duration kEventBatchFlushInterval = Duration(milliseconds: 500);

/// shared_preferences key that remembers the last selected shooter.
const String kPrefsLastShooterIdKey = 'atriarch.last_shooter_id';
```

- [ ] **Step 2: Commit**

```bash
git add lib/constants.dart
git commit -m "feat(persistence): add project constants for DB + shooter identity"
```

---

## Task 3: Schema SQL

**Files:**
- Create: `lib/db/schema.dart`
- Test: `test/db/database_helper_test.dart` (schema assertions arrive in Task 4)

- [ ] **Step 1: Write the schema SQL**

```dart
// lib/db/schema.dart
//
// SQLite schema v1 — defined as raw SQL constants. DatabaseHelper runs these
// in onCreate. Every migration going forward adds an onUpgrade step; we never
// edit v1 strings after release.

const List<String> kSchemaV1Ddl = [
  // --- PROFILES -----------------------------------------------------------
  '''
  CREATE TABLE shooters (
    id TEXT PRIMARY KEY NOT NULL,
    display_name TEXT NOT NULL,
    contact_email TEXT,
    contact_phone TEXT,
    created_at INTEGER NOT NULL,
    range_buddy_user_id TEXT
  )
  ''',

  // --- CONFIG -------------------------------------------------------------
  '''
  CREATE TABLE drill_templates (
    id TEXT PRIMARY KEY NOT NULL,
    shooter_id TEXT,
    name TEXT NOT NULL,
    program_type TEXT NOT NULL,
    config_json TEXT NOT NULL,
    config_hash TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (shooter_id) REFERENCES shooters(id) ON DELETE SET NULL
  )
  ''',

  // --- RAW (source of truth) ----------------------------------------------
  '''
  CREATE TABLE sessions (
    id TEXT PRIMARY KEY NOT NULL,
    shooter_id TEXT NOT NULL,
    template_id TEXT,
    program_type TEXT NOT NULL,
    config_json TEXT NOT NULL,
    config_hash TEXT NOT NULL,
    started_at INTEGER NOT NULL,
    ended_at INTEGER,
    finished_normally INTEGER NOT NULL DEFAULT 0,
    iterations_completed INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (shooter_id) REFERENCES shooters(id) ON DELETE CASCADE,
    FOREIGN KEY (template_id) REFERENCES drill_templates(id) ON DELETE SET NULL
  )
  ''',

  '''
  CREATE TABLE session_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    sequence INTEGER NOT NULL,
    type TEXT NOT NULL,
    target_id INTEGER,
    hit_number INTEGER,
    required_hits INTEGER,
    total_time_ms INTEGER,
    error_detail TEXT,
    timestamp INTEGER NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
  )
  ''',

  // --- DERIVED (cache, populated in Plan 2) -------------------------------
  '''
  CREATE TABLE session_metrics (
    session_id TEXT PRIMARY KEY NOT NULL,
    draw_ms INTEGER,
    total_duration_ms INTEGER,
    total_rounds_fired INTEGER NOT NULL DEFAULT 0,
    no_shoot_count INTEGER NOT NULL DEFAULT 0,
    late_hit_count INTEGER NOT NULL DEFAULT 0,
    avg_reaction_ms INTEGER,
    median_reaction_ms INTEGER,
    avg_split_ms INTEGER,
    avg_transition_ms INTEGER,
    stddev_reaction_ms INTEGER,
    data_quality_warning INTEGER NOT NULL DEFAULT 0,
    metrics_version INTEGER NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
  )
  ''',

  '''
  CREATE TABLE target_engagements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    target_id INTEGER NOT NULL,
    engagement_index INTEGER NOT NULL,
    activated_at INTEGER NOT NULL,
    preceding_delay_ms INTEGER NOT NULL,
    reaction_ms INTEGER,
    hits_landed INTEGER NOT NULL DEFAULT 0,
    required_hits INTEGER NOT NULL,
    engagement_time_ms INTEGER,
    was_no_shoot INTEGER NOT NULL DEFAULT 0,
    had_late_hit INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
  )
  ''',

  // --- INDEXES ------------------------------------------------------------
  'CREATE INDEX idx_sessions_shooter_started ON sessions(shooter_id, started_at DESC)',
  'CREATE INDEX idx_session_events_session_seq ON session_events(session_id, sequence)',
  'CREATE INDEX idx_target_engagements_session ON target_engagements(session_id)',
  'CREATE INDEX idx_target_engagements_session_target ON target_engagements(session_id, target_id)',
];

/// SQL to seed the reserved "Unassigned" shooter. Run once in onCreate.
/// Parameters are bound at call site (see DatabaseHelper).
const String kSeedUnassignedShooterSql = '''
INSERT INTO shooters (id, display_name, created_at)
VALUES (?, ?, ?)
''';
```

- [ ] **Step 2: Commit**

```bash
git add lib/db/schema.dart
git commit -m "feat(persistence): add schema v1 DDL for shooters, sessions, events, metrics, engagements"
```

---

## Task 4: DatabaseHelper + test

**Files:**
- Create: `lib/db/database_helper.dart`
- Create: `test/test_helpers/test_database.dart`
- Create: `test/db/database_helper_test.dart`

- [ ] **Step 1: Write the test helper**

```dart
// test/test_helpers/test_database.dart
//
// Initializes sqflite to use the FFI backend (host-side, no device required)
// and hands back a fresh in-memory Database for each test.

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Call once per test run (idempotent) to install the FFI factory.
void initializeTestDatabase() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// Returns a fresh in-memory DB with schema v1 applied.
Future<Database> openTestDatabase({int version = 1}) async {
  initializeTestDatabase();
  return databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, v) async {
        // Import the real schema & seed without tying tests to DatabaseHelper's
        // file-system path logic.
        // Note: this block is overridden in database_helper_test.dart by
        // passing a custom onCreate. Keep this default for other suites.
      },
    ),
  );
}
```

- [ ] **Step 2: Write the failing test**

```dart
// test/db/database_helper_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/constants.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() {
    initializeTestDatabase();
  });

  group('DatabaseHelper schema v1', () {
    late Database db;

    setUp(() async {
      db = await DatabaseHelper.openForTesting();
    });

    tearDown(() async {
      await db.close();
    });

    test('all six tables exist', () async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
      );
      final names = tables.map((r) => r['name'] as String).toSet();
      expect(names, containsAll({
        'shooters',
        'drill_templates',
        'sessions',
        'session_events',
        'session_metrics',
        'target_engagements',
      }));
    });

    test('expected indexes exist', () async {
      final idx = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'",
      );
      final names = idx.map((r) => r['name'] as String).toSet();
      expect(names, containsAll({
        'idx_sessions_shooter_started',
        'idx_session_events_session_seq',
        'idx_target_engagements_session',
        'idx_target_engagements_session_target',
      }));
    });

    test('Unassigned shooter is seeded', () async {
      final rows = await db.query(
        'shooters',
        where: 'id = ?',
        whereArgs: [kUnassignedShooterId],
      );
      expect(rows, hasLength(1));
      expect(rows.first['display_name'], kUnassignedShooterName);
    });

    test('foreign keys are enforced', () async {
      // Attempting to insert a session with a non-existent shooter_id fails.
      expect(
        () => db.insert('sessions', {
          'id': 'test-session',
          'shooter_id': 'nonexistent',
          'program_type': 'A',
          'config_json': '{}',
          'config_hash': 'abc',
          'started_at': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/db/database_helper_test.dart`
Expected: FAIL — `DatabaseHelper` class not yet defined.

- [ ] **Step 4: Implement DatabaseHelper**

```dart
// lib/db/database_helper.dart
//
// sqflite wrapper: singleton for the app, test-friendly via openForTesting().

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi;

import '../constants.dart';
import 'schema.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static Database? _instance;

  /// Returns the singleton DB, opening on first call. Production app path.
  static Future<Database> instance() async {
    final existing = _instance;
    if (existing != null) return existing;
    final docsDir = await getApplicationDocumentsDirectory();
    final path = p.join(docsDir.path, kDatabaseFileName);
    final db = await openDatabase(
      path,
      version: kDatabaseVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
    );
    _instance = db;
    return db;
  }

  /// Opens a fresh in-memory DB for tests. Does NOT populate `_instance`.
  /// Caller owns close().
  static Future<Database> openForTesting() async {
    return databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: kDatabaseVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
      ),
    );
  }

  /// Resets the singleton. Tests only.
  @visibleForTesting
  static Future<void> resetForTesting() async {
    await _instance?.close();
    _instance = null;
  }

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    for (final stmt in kSchemaV1Ddl) {
      batch.execute(stmt);
    }
    batch.rawInsert(
      kSeedUnassignedShooterSql,
      [
        kUnassignedShooterId,
        kUnassignedShooterName,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    await batch.commit(noResult: true);
  }
}
```

Also add `import 'package:flutter/foundation.dart';` at the top if `@visibleForTesting` is missing.

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/db/database_helper_test.dart`
Expected: all 4 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/db/database_helper.dart test/test_helpers/test_database.dart test/db/database_helper_test.dart
git commit -m "feat(persistence): DatabaseHelper with schema v1, FK enforcement, Unassigned seed"
```

---

## Task 5: Shooter model

**Files:**
- Create: `lib/models/shooter.dart`
- Create: `test/models/shooter_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/models/shooter_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/models/shooter.dart';

void main() {
  group('Shooter', () {
    test('round-trips through toMap / fromMap with all fields', () {
      final s = Shooter(
        id: 'abc-uuid',
        displayName: 'Jeremy',
        contactEmail: 'j@example.com',
        contactPhone: '+14155551234',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1745176800000),
        rangeBuddyUserId: 'rb-123',
      );
      final map = s.toMap();
      final back = Shooter.fromMap(map);
      expect(back.id, s.id);
      expect(back.displayName, s.displayName);
      expect(back.contactEmail, s.contactEmail);
      expect(back.contactPhone, s.contactPhone);
      expect(back.createdAt, s.createdAt);
      expect(back.rangeBuddyUserId, s.rangeBuddyUserId);
    });

    test('round-trips with null optional fields', () {
      final s = Shooter(
        id: 'abc-uuid',
        displayName: 'Jeremy',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1745176800000),
      );
      final back = Shooter.fromMap(s.toMap());
      expect(back.contactEmail, isNull);
      expect(back.contactPhone, isNull);
      expect(back.rangeBuddyUserId, isNull);
    });

    test('equality is value-based', () {
      final a = Shooter(
        id: 'x',
        displayName: 'A',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final b = Shooter(
        id: 'x',
        displayName: 'A',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/shooter_test.dart`
Expected: FAIL — `Shooter` class not defined.

- [ ] **Step 3: Implement Shooter**

```dart
// lib/models/shooter.dart

import 'package:flutter/foundation.dart';

@immutable
class Shooter {
  final String id;
  final String displayName;
  final String? contactEmail;
  final String? contactPhone;
  final DateTime createdAt;
  final String? rangeBuddyUserId;

  const Shooter({
    required this.id,
    required this.displayName,
    required this.createdAt,
    this.contactEmail,
    this.contactPhone,
    this.rangeBuddyUserId,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'display_name': displayName,
        'contact_email': contactEmail,
        'contact_phone': contactPhone,
        'created_at': createdAt.millisecondsSinceEpoch,
        'range_buddy_user_id': rangeBuddyUserId,
      };

  factory Shooter.fromMap(Map<String, Object?> m) => Shooter(
        id: m['id'] as String,
        displayName: m['display_name'] as String,
        contactEmail: m['contact_email'] as String?,
        contactPhone: m['contact_phone'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        rangeBuddyUserId: m['range_buddy_user_id'] as String?,
      );

  Shooter copyWith({
    String? displayName,
    String? contactEmail,
    String? contactPhone,
    String? rangeBuddyUserId,
  }) =>
      Shooter(
        id: id,
        displayName: displayName ?? this.displayName,
        createdAt: createdAt,
        contactEmail: contactEmail ?? this.contactEmail,
        contactPhone: contactPhone ?? this.contactPhone,
        rangeBuddyUserId: rangeBuddyUserId ?? this.rangeBuddyUserId,
      );

  @override
  bool operator ==(Object other) =>
      other is Shooter &&
      other.id == id &&
      other.displayName == displayName &&
      other.contactEmail == contactEmail &&
      other.contactPhone == contactPhone &&
      other.createdAt == createdAt &&
      other.rangeBuddyUserId == rangeBuddyUserId;

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        contactEmail,
        contactPhone,
        createdAt,
        rangeBuddyUserId,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/shooter_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/shooter.dart test/models/shooter_test.dart
git commit -m "feat(persistence): Shooter model with toMap/fromMap and value equality"
```

---

## Task 6: ContactValidator (email + E.164 phone)

**Files:**
- Create: `lib/services/contact_validator.dart`
- Create: `test/services/contact_validator_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/services/contact_validator_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/services/contact_validator.dart';

void main() {
  group('ContactValidator.isValidEmail', () {
    test('accepts simple valid addresses', () {
      expect(ContactValidator.isValidEmail('a@b.co'), isTrue);
      expect(ContactValidator.isValidEmail('jeremy.gill@example.com'), isTrue);
      expect(ContactValidator.isValidEmail('a+tag@b.io'), isTrue);
    });

    test('rejects obvious non-emails', () {
      expect(ContactValidator.isValidEmail(''), isFalse);
      expect(ContactValidator.isValidEmail('no-at-sign'), isFalse);
      expect(ContactValidator.isValidEmail('@nolocal.com'), isFalse);
      expect(ContactValidator.isValidEmail('no@domain'), isFalse);
      expect(ContactValidator.isValidEmail('spaces @ok.com'), isFalse);
    });
  });

  group('ContactValidator.normalizePhone', () {
    test('normalizes US-style inputs to E.164', () {
      expect(ContactValidator.normalizePhone('(415) 555-1234'), '+14155551234');
      expect(ContactValidator.normalizePhone('415.555.1234'), '+14155551234');
      expect(ContactValidator.normalizePhone('415-555-1234'), '+14155551234');
      expect(ContactValidator.normalizePhone('4155551234'), '+14155551234');
    });

    test('keeps already-E.164 inputs unchanged', () {
      expect(ContactValidator.normalizePhone('+14155551234'), '+14155551234');
      expect(ContactValidator.normalizePhone('+442071234567'), '+442071234567');
    });

    test('returns null for unparseable inputs', () {
      expect(ContactValidator.normalizePhone(''), isNull);
      expect(ContactValidator.normalizePhone('abc'), isNull);
      expect(ContactValidator.normalizePhone('123'), isNull);  // too short
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/contact_validator_test.dart`
Expected: FAIL — `ContactValidator` not defined.

- [ ] **Step 3: Implement ContactValidator**

```dart
// lib/services/contact_validator.dart
//
// Email format validation + phone E.164 normalization.
// Deliberately permissive: we save invalid inputs as-is (with a UI warning),
// we do not BLOCK the save. These helpers are the warn-check.

class ContactValidator {
  /// Simple RFC-5322-ish check. Not exhaustive; just catches obvious typos.
  static bool isValidEmail(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(trimmed);
  }

  /// Returns the phone in E.164 format (leading `+`, country code, digits).
  /// Returns null if the input can't be reasonably parsed. Rules:
  /// - If already starts with `+`, strip non-digits after the `+` and require
  ///   the result to have 8–15 digits after the `+`.
  /// - If 10 digits, assume US and prefix `+1`.
  /// - If 11 digits starting with `1`, prefix `+`.
  /// - Otherwise null.
  static String? normalizePhone(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('+')) {
      final digits = trimmed.substring(1).replaceAll(RegExp(r'\D'), '');
      if (digits.length < 8 || digits.length > 15) return null;
      return '+$digits';
    }

    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '+1$digits';
    if (digits.length == 11 && digits.startsWith('1')) return '+$digits';
    return null;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/contact_validator_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/contact_validator.dart test/services/contact_validator_test.dart
git commit -m "feat(persistence): ContactValidator for email + E.164 phone normalization"
```

---

## Task 7: ShooterRepository (CRUD)

**Files:**
- Create: `lib/repositories/shooter_repository.dart`
- Create: `test/repositories/shooter_repository_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/repositories/shooter_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/constants.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() => initializeTestDatabase());

  group('ShooterRepository', () {
    late Database db;
    late ShooterRepository repo;

    setUp(() async {
      db = await DatabaseHelper.openForTesting();
      repo = ShooterRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('listAll returns the seeded Unassigned shooter after init', () async {
      final all = await repo.listAll();
      expect(all.map((s) => s.id), contains(kUnassignedShooterId));
    });

    test('insert and getById round-trip', () async {
      final s = Shooter(
        id: 'uuid-jeremy',
        displayName: 'Jeremy',
        contactEmail: 'j@example.com',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      await repo.insert(s);
      final back = await repo.getById('uuid-jeremy');
      expect(back, s);
    });

    test('getById returns null for unknown id', () async {
      expect(await repo.getById('nope'), isNull);
    });

    test('update modifies display_name and keeps id stable', () async {
      final s = Shooter(
        id: 'uuid-a',
        displayName: 'Old',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      await repo.insert(s);
      await repo.update(s.copyWith(displayName: 'New'));
      expect((await repo.getById('uuid-a'))!.displayName, 'New');
    });

    test('delete removes the row and cascades to sessions (empty cascade)', () async {
      final s = Shooter(
        id: 'uuid-del',
        displayName: 'Del',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      await repo.insert(s);
      await repo.delete('uuid-del');
      expect(await repo.getById('uuid-del'), isNull);
    });

    test('cannot delete the Unassigned reserved shooter', () async {
      expect(
        () => repo.delete(kUnassignedShooterId),
        throwsA(isA<StateError>()),
      );
    });

    test('listAll orders by created_at DESC', () async {
      await repo.insert(Shooter(
        id: 'old',
        displayName: 'Old',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
      await repo.insert(Shooter(
        id: 'new',
        displayName: 'New',
        createdAt: DateTime.fromMillisecondsSinceEpoch(5000),
      ));
      final ids = (await repo.listAll()).map((s) => s.id).toList();
      // Unassigned was seeded with now() in onCreate, which is > 5000, so it
      // lands first. Filter it out for the ordering assertion.
      final nonReserved = ids.where((id) => id != kUnassignedShooterId).toList();
      expect(nonReserved, ['new', 'old']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/shooter_repository_test.dart`
Expected: FAIL — `ShooterRepository` not defined.

- [ ] **Step 3: Implement ShooterRepository**

```dart
// lib/repositories/shooter_repository.dart

import 'package:sqflite/sqflite.dart';

import '../constants.dart';
import '../models/shooter.dart';

class ShooterRepository {
  final Database _db;
  ShooterRepository(this._db);

  Future<void> insert(Shooter s) async {
    await _db.insert(
      'shooters',
      s.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<Shooter?> getById(String id) async {
    final rows = await _db.query(
      'shooters',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Shooter.fromMap(rows.first);
  }

  Future<List<Shooter>> listAll() async {
    final rows = await _db.query(
      'shooters',
      orderBy: 'created_at DESC',
    );
    return rows.map(Shooter.fromMap).toList();
  }

  Future<void> update(Shooter s) async {
    await _db.update(
      'shooters',
      s.toMap(),
      where: 'id = ?',
      whereArgs: [s.id],
    );
  }

  Future<void> delete(String id) async {
    if (id == kUnassignedShooterId) {
      throw StateError('Cannot delete reserved Unassigned shooter');
    }
    await _db.delete(
      'shooters',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/shooter_repository_test.dart`
Expected: PASS (all 7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/shooter_repository.dart test/repositories/shooter_repository_test.dart
git commit -m "feat(persistence): ShooterRepository with insert/get/list/update/delete + Unassigned guard"
```

---

## Task 8: ConfigHasher

**Files:**
- Create: `lib/services/config_hasher.dart`
- Create: `test/services/config_hasher_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/services/config_hasher_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/target_group.dart';
import 'package:atriarch/services/config_hasher.dart';

DrillConfig _mkConfigA() => DrillConfig(
      programType: ProgramType.programA,
      startMin: 1.0,
      startMax: 3.0,
      delayMin: 0.5,
      delayMax: 2.0,
      hitsMin: 1,
      hitsMax: 3,
      groups: [TargetGroup(targetIds: [1, 2])],
      targetIds: [],
      noShootIds: [5],
      iterations: 5,
    );

void main() {
  group('ConfigHasher', () {
    test('same config produces same hash', () {
      final h1 = ConfigHasher.hash(_mkConfigA());
      final h2 = ConfigHasher.hash(_mkConfigA());
      expect(h1, h2);
    });

    test('different program_type produces different hash', () {
      final a = _mkConfigA();
      final b = _mkConfigA()..programType = ProgramType.programB;
      expect(ConfigHasher.hash(a), isNot(ConfigHasher.hash(b)));
    });

    test('different startMin produces different hash', () {
      final a = _mkConfigA();
      final b = _mkConfigA()..startMin = 2.0;
      expect(ConfigHasher.hash(a), isNot(ConfigHasher.hash(b)));
    });

    test('different iterations produces different hash', () {
      final a = _mkConfigA();
      final b = _mkConfigA()..iterations = 10;
      expect(ConfigHasher.hash(a), isNot(ConfigHasher.hash(b)));
    });

    test('hash is a 64-char sha256 hex string', () {
      final h = ConfigHasher.hash(_mkConfigA());
      expect(h, hasLength(64));
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(h), isTrue);
    });

    test('canonicalJson output is stable across calls', () {
      final a = _mkConfigA();
      final j1 = ConfigHasher.canonicalJson(a);
      final j2 = ConfigHasher.canonicalJson(a);
      expect(j1, j2);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/config_hasher_test.dart`
Expected: FAIL — `ConfigHasher` not defined.

- [ ] **Step 3: Implement ConfigHasher**

```dart
// lib/services/config_hasher.dart
//
// Canonical JSON serialization of DrillConfig → sha256 hex.
// "Canonical" = sorted keys at every level, deterministic list ordering,
// so two equivalent DrillConfigs always produce the same hash.

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/drill_config.dart';
import '../models/target_group.dart';

class ConfigHasher {
  /// Returns the canonical JSON string for a DrillConfig.
  /// Public so callers can also persist the same json alongside the hash.
  static String canonicalJson(DrillConfig c) {
    final map = <String, Object?>{
      'programType': _programTypeString(c.programType),
      'startMin': c.startMin,
      'startMax': c.startMax,
      'delayMin': c.delayMin,
      'delayMax': c.delayMax,
      'hitsMin': c.hitsMin,
      'hitsMax': c.hitsMax,
      'groups': c.groups.map(_groupToJson).toList(),
      'targetIds': [...c.targetIds]..sort(),
      'noShootIds': [...c.noShootIds]..sort(),
      'iterations': c.iterations,
    };
    return _jsonEncodeSorted(map);
  }

  /// Returns sha256 of canonical JSON as a 64-char lowercase hex string.
  static String hash(DrillConfig c) {
    final bytes = utf8.encode(canonicalJson(c));
    return sha256.convert(bytes).toString();
  }

  static String _programTypeString(ProgramType t) =>
      t == ProgramType.programA ? 'A' : 'B';

  static Map<String, Object?> _groupToJson(TargetGroup g) => {
        'targetIds': [...g.targetIds]..sort(),
      };

  static String _jsonEncodeSorted(Object? value) {
    // Recursively re-encode maps with sorted keys.
    Object? norm(Object? v) {
      if (v is Map) {
        final sorted = <String, Object?>{};
        final keys = v.keys.cast<String>().toList()..sort();
        for (final k in keys) {
          sorted[k] = norm(v[k]);
        }
        return sorted;
      }
      if (v is List) return v.map(norm).toList();
      return v;
    }

    return jsonEncode(norm(value));
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/config_hasher_test.dart`
Expected: PASS (all 6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/config_hasher.dart test/services/config_hasher_test.dart
git commit -m "feat(persistence): ConfigHasher — canonical JSON + sha256 of DrillConfig"
```

---

## Task 9: SessionRecord model

**Files:**
- Create: `lib/models/session_record.dart`
- Create: `test/models/session_record_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/models/session_record_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/models/session_record.dart';

void main() {
  group('SessionRecord', () {
    test('round-trips toMap/fromMap with all fields', () {
      final r = SessionRecord(
        id: 'sess-uuid',
        shooterId: 'shooter-uuid',
        templateId: 'tpl-uuid',
        programType: 'A',
        configJson: '{"programType":"A"}',
        configHash: 'abc123',
        startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        endedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        finishedNormally: true,
        iterationsCompleted: 3,
      );
      final back = SessionRecord.fromMap(r.toMap());
      expect(back.id, r.id);
      expect(back.shooterId, r.shooterId);
      expect(back.templateId, r.templateId);
      expect(back.programType, r.programType);
      expect(back.configJson, r.configJson);
      expect(back.configHash, r.configHash);
      expect(back.startedAt, r.startedAt);
      expect(back.endedAt, r.endedAt);
      expect(back.finishedNormally, true);
      expect(back.iterationsCompleted, 3);
    });

    test('round-trips with null ended_at and false finished_normally', () {
      final r = SessionRecord(
        id: 'sess',
        shooterId: 'sh',
        templateId: null,
        programType: 'B',
        configJson: '{}',
        configHash: 'h',
        startedAt: DateTime.fromMillisecondsSinceEpoch(0),
        endedAt: null,
        finishedNormally: false,
        iterationsCompleted: 0,
      );
      final back = SessionRecord.fromMap(r.toMap());
      expect(back.endedAt, isNull);
      expect(back.finishedNormally, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/session_record_test.dart`
Expected: FAIL — `SessionRecord` not defined.

- [ ] **Step 3: Implement SessionRecord**

```dart
// lib/models/session_record.dart
//
// Maps 1:1 to a row in the `sessions` table. Distinct from DrillSession
// (the in-memory live-drill accumulator in lib/models/drill_session.dart).

import 'package:flutter/foundation.dart';

@immutable
class SessionRecord {
  final String id;
  final String shooterId;
  final String? templateId;
  final String programType;       // 'A' | 'B'
  final String configJson;
  final String configHash;
  final DateTime startedAt;
  final DateTime? endedAt;
  final bool finishedNormally;
  final int iterationsCompleted;

  const SessionRecord({
    required this.id,
    required this.shooterId,
    required this.programType,
    required this.configJson,
    required this.configHash,
    required this.startedAt,
    required this.finishedNormally,
    required this.iterationsCompleted,
    this.templateId,
    this.endedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'shooter_id': shooterId,
        'template_id': templateId,
        'program_type': programType,
        'config_json': configJson,
        'config_hash': configHash,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'finished_normally': finishedNormally ? 1 : 0,
        'iterations_completed': iterationsCompleted,
      };

  factory SessionRecord.fromMap(Map<String, Object?> m) => SessionRecord(
        id: m['id'] as String,
        shooterId: m['shooter_id'] as String,
        templateId: m['template_id'] as String?,
        programType: m['program_type'] as String,
        configJson: m['config_json'] as String,
        configHash: m['config_hash'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        endedAt: m['ended_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['ended_at'] as int),
        finishedNormally: (m['finished_normally'] as int) == 1,
        iterationsCompleted: m['iterations_completed'] as int,
      );

  SessionRecord copyWith({
    String? templateId,
    DateTime? endedAt,
    bool? finishedNormally,
    int? iterationsCompleted,
  }) =>
      SessionRecord(
        id: id,
        shooterId: shooterId,
        programType: programType,
        configJson: configJson,
        configHash: configHash,
        startedAt: startedAt,
        templateId: templateId ?? this.templateId,
        endedAt: endedAt ?? this.endedAt,
        finishedNormally: finishedNormally ?? this.finishedNormally,
        iterationsCompleted: iterationsCompleted ?? this.iterationsCompleted,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/session_record_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/session_record.dart test/models/session_record_test.dart
git commit -m "feat(persistence): SessionRecord model (sessions table row)"
```

---

## Task 10: SessionRepository

**Files:**
- Create: `lib/repositories/session_repository.dart`
- Create: `test/repositories/session_repository_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/repositories/session_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/models/session_record.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/session_repository.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() => initializeTestDatabase());

  group('SessionRepository', () {
    late Database db;
    late SessionRepository sessions;
    late ShooterRepository shooters;

    setUp(() async {
      db = await DatabaseHelper.openForTesting();
      sessions = SessionRepository(db);
      shooters = ShooterRepository(db);
      await shooters.insert(Shooter(
        id: 'sh-1',
        displayName: 'Test',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ));
    });

    tearDown(() async {
      await db.close();
    });

    SessionRecord mkSession({String id = 's1', DateTime? startedAt}) =>
        SessionRecord(
          id: id,
          shooterId: 'sh-1',
          programType: 'A',
          configJson: '{}',
          configHash: 'hash',
          startedAt: startedAt ?? DateTime.fromMillisecondsSinceEpoch(1000),
          finishedNormally: false,
          iterationsCompleted: 0,
        );

    test('insert + getById round-trip', () async {
      await sessions.insert(mkSession());
      final back = await sessions.getById('s1');
      expect(back!.id, 's1');
      expect(back.finishedNormally, isFalse);
    });

    test('appendEvents persists in order with monotonic sequences', () async {
      await sessions.insert(mkSession());
      await sessions.appendEvents('s1', [
        SessionEvent(type: EventType.targetActivated, targetId: 1),
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1),
      ]);
      final rows = await db.query(
        'session_events',
        where: 'session_id = ?',
        whereArgs: ['s1'],
        orderBy: 'sequence ASC',
      );
      expect(rows, hasLength(2));
      expect(rows[0]['sequence'], 0);
      expect(rows[1]['sequence'], 1);
      expect(rows[0]['type'], 'ACT');
      expect(rows[1]['type'], 'HIT');
    });

    test('appendEvents continues sequence after prior append', () async {
      await sessions.insert(mkSession());
      await sessions.appendEvents('s1', [
        SessionEvent(type: EventType.targetActivated, targetId: 1),
      ]);
      await sessions.appendEvents('s1', [
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1),
      ]);
      final rows = await db.query(
        'session_events',
        where: 'session_id = ?',
        whereArgs: ['s1'],
        orderBy: 'sequence ASC',
      );
      expect(rows.map((r) => r['sequence']), [0, 1]);
    });

    test('closeSession sets ended_at + finished_normally', () async {
      await sessions.insert(mkSession());
      await sessions.closeSession(
        id: 's1',
        endedAt: DateTime.fromMillisecondsSinceEpoch(5000),
        finishedNormally: true,
        iterationsCompleted: 5,
      );
      final back = (await sessions.getById('s1'))!;
      expect(back.endedAt, DateTime.fromMillisecondsSinceEpoch(5000));
      expect(back.finishedNormally, isTrue);
      expect(back.iterationsCompleted, 5);
    });

    test('findOrphanSessions returns sessions with ended_at NULL', () async {
      await sessions.insert(mkSession(id: 'open'));
      await sessions.insert(mkSession(id: 'closed'));
      await sessions.closeSession(
        id: 'closed',
        endedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        finishedNormally: true,
        iterationsCompleted: 1,
      );
      final orphans = await sessions.findOrphanSessions();
      expect(orphans.map((s) => s.id), ['open']);
    });

    test('deleting a shooter cascades to sessions and events', () async {
      await sessions.insert(mkSession());
      await sessions.appendEvents('s1', [
        SessionEvent(type: EventType.targetActivated, targetId: 1),
      ]);
      await shooters.delete('sh-1');
      expect(await sessions.getById('s1'), isNull);
      final evts = await db.query('session_events', where: 'session_id = ?', whereArgs: ['s1']);
      expect(evts, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/session_repository_test.dart`
Expected: FAIL — `SessionRepository` not defined.

- [ ] **Step 3: Implement SessionRepository**

```dart
// lib/repositories/session_repository.dart

import 'package:sqflite/sqflite.dart';

import '../models/session_event.dart';
import '../models/session_record.dart';

class SessionRepository {
  final Database _db;
  SessionRepository(this._db);

  Future<void> insert(SessionRecord r) async {
    await _db.insert(
      'sessions',
      r.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<SessionRecord?> getById(String id) async {
    final rows = await _db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SessionRecord.fromMap(rows.first);
  }

  /// Append a batch of events to a session. Sequence numbers are assigned
  /// contiguously starting from (max existing sequence + 1), or 0 if empty.
  Future<void> appendEvents(String sessionId, List<SessionEvent> events) async {
    if (events.isEmpty) return;
    await _db.transaction((txn) async {
      final result = await txn.rawQuery(
        'SELECT COALESCE(MAX(sequence), -1) AS max_seq FROM session_events WHERE session_id = ?',
        [sessionId],
      );
      var nextSeq = (result.first['max_seq'] as int) + 1;
      final batch = txn.batch();
      for (final e in events) {
        batch.insert('session_events', {
          'session_id': sessionId,
          'sequence': nextSeq++,
          'type': _typeToCode(e.type),
          'target_id': e.targetId,
          'hit_number': e.hitNumber,
          'required_hits': e.requiredHits,
          'total_time_ms': e.totalTimeMs,
          'error_detail': e.errorDetail,
          'timestamp': e.timestamp.millisecondsSinceEpoch,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> closeSession({
    required String id,
    required DateTime endedAt,
    required bool finishedNormally,
    required int iterationsCompleted,
  }) async {
    await _db.update(
      'sessions',
      {
        'ended_at': endedAt.millisecondsSinceEpoch,
        'finished_normally': finishedNormally ? 1 : 0,
        'iterations_completed': iterationsCompleted,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<SessionRecord>> findOrphanSessions() async {
    final rows = await _db.query(
      'sessions',
      where: 'ended_at IS NULL',
    );
    return rows.map(SessionRecord.fromMap).toList();
  }

  /// Returns the timestamp of the last event in a session, or null if none.
  Future<DateTime?> lastEventTimestamp(String sessionId) async {
    final rows = await _db.rawQuery(
      'SELECT MAX(timestamp) AS ts FROM session_events WHERE session_id = ?',
      [sessionId],
    );
    final ts = rows.first['ts'];
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts as int);
  }

  static String _typeToCode(EventType t) {
    switch (t) {
      case EventType.targetActivated:
        return 'ACT';
      case EventType.hitDetected:
        return 'HIT';
      case EventType.targetComplete:
        return 'DONE';
      case EventType.noShootViolation:
        return 'NS';
      case EventType.lateHit:
        return 'LATE';
      case EventType.drillFinished:
        return 'FIN';
      case EventType.error:
        return 'ERROR';
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/session_repository_test.dart`
Expected: PASS (all 6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/session_repository.dart test/repositories/session_repository_test.dart
git commit -m "feat(persistence): SessionRepository with insert/append/close/findOrphans"
```

---

## Task 11: EventBatcher

**Files:**
- Create: `lib/services/event_batcher.dart`
- Create: `test/services/event_batcher_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/services/event_batcher_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/services/event_batcher.dart';

void main() {
  group('EventBatcher', () {
    test('buffers events until flush interval elapses', () async {
      final flushed = <List<SessionEvent>>[];
      final batcher = EventBatcher(
        onFlush: (events) async => flushed.add(events),
        flushInterval: const Duration(milliseconds: 50),
      );

      batcher.start();
      batcher.add(SessionEvent(type: EventType.targetActivated, targetId: 1));
      batcher.add(SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1));

      expect(flushed, isEmpty);

      await Future.delayed(const Duration(milliseconds: 80));

      expect(flushed, hasLength(1));
      expect(flushed.first, hasLength(2));

      await batcher.stop();
    });

    test('stop() performs final flush of buffered events', () async {
      final flushed = <List<SessionEvent>>[];
      final batcher = EventBatcher(
        onFlush: (events) async => flushed.add(events),
        flushInterval: const Duration(seconds: 10),
      );
      batcher.start();
      batcher.add(SessionEvent(type: EventType.targetActivated, targetId: 1));
      await batcher.stop();
      expect(flushed, hasLength(1));
      expect(flushed.first, hasLength(1));
    });

    test('does not flush empty buffers', () async {
      final flushed = <List<SessionEvent>>[];
      final batcher = EventBatcher(
        onFlush: (events) async => flushed.add(events),
        flushInterval: const Duration(milliseconds: 30),
      );
      batcher.start();
      await Future.delayed(const Duration(milliseconds: 70));
      await batcher.stop();
      expect(flushed, isEmpty);
    });

    test('add() before start() is ignored (guard against leaks)', () async {
      final flushed = <List<SessionEvent>>[];
      final batcher = EventBatcher(
        onFlush: (events) async => flushed.add(events),
        flushInterval: const Duration(milliseconds: 10),
      );
      batcher.add(SessionEvent(type: EventType.targetActivated, targetId: 1));
      batcher.start();
      await Future.delayed(const Duration(milliseconds: 30));
      await batcher.stop();
      expect(flushed, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/event_batcher_test.dart`
Expected: FAIL — `EventBatcher` not defined.

- [ ] **Step 3: Implement EventBatcher**

```dart
// lib/services/event_batcher.dart
//
// Buffers SessionEvents during a live drill; flushes them to onFlush on a
// timer (default 500ms) and on stop(). Keeps the drill-hot path off per-event
// fsync latency.

import 'dart:async';

import '../constants.dart';
import '../models/session_event.dart';

typedef EventFlushCallback = Future<void> Function(List<SessionEvent> events);

class EventBatcher {
  final EventFlushCallback onFlush;
  final Duration flushInterval;

  final List<SessionEvent> _buffer = [];
  Timer? _timer;
  bool _running = false;

  EventBatcher({
    required this.onFlush,
    this.flushInterval = kEventBatchFlushInterval,
  });

  void start() {
    if (_running) return;
    _running = true;
    _buffer.clear();
    _timer = Timer.periodic(flushInterval, (_) => _flush());
  }

  void add(SessionEvent event) {
    if (!_running) return;
    _buffer.add(event);
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    await _flush();
  }

  Future<void> _flush() async {
    if (_buffer.isEmpty) return;
    final toSend = List<SessionEvent>.unmodifiable(_buffer);
    _buffer.clear();
    await onFlush(toSend);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/event_batcher_test.dart`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/event_batcher.dart test/services/event_batcher_test.dart
git commit -m "feat(persistence): EventBatcher buffers drill events on 500ms flush cadence"
```

---

## Task 12: OrphanRecovery

**Files:**
- Create: `lib/services/orphan_recovery.dart`
- Create: `test/services/orphan_recovery_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/services/orphan_recovery_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/models/session_record.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/session_repository.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import 'package:atriarch/services/orphan_recovery.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() => initializeTestDatabase());

  group('OrphanRecovery.sweep', () {
    late Database db;
    late SessionRepository sessions;

    setUp(() async {
      db = await DatabaseHelper.openForTesting();
      sessions = SessionRepository(db);
      await ShooterRepository(db).insert(Shooter(
        id: 'sh',
        displayName: 'X',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ));
    });

    tearDown(() => db.close());

    test('closes orphan with ended_at = last event timestamp', () async {
      await sessions.insert(SessionRecord(
        id: 'orphan',
        shooterId: 'sh',
        programType: 'A',
        configJson: '{}',
        configHash: 'h',
        startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        finishedNormally: false,
        iterationsCompleted: 0,
      ));
      await sessions.appendEvents('orphan', [
        SessionEvent(type: EventType.targetActivated, targetId: 1),
      ]);
      // Force the event timestamp by direct SQL (SessionEvent uses now()).
      await db.update(
        'session_events',
        {'timestamp': 2500},
        where: 'session_id = ?',
        whereArgs: ['orphan'],
      );

      final count = await OrphanRecovery.sweep(sessions);

      expect(count, 1);
      final back = (await sessions.getById('orphan'))!;
      expect(back.endedAt, DateTime.fromMillisecondsSinceEpoch(2500));
      expect(back.finishedNormally, isFalse);
    });

    test('closes orphan with no events using started_at as ended_at', () async {
      await sessions.insert(SessionRecord(
        id: 'empty',
        shooterId: 'sh',
        programType: 'A',
        configJson: '{}',
        configHash: 'h',
        startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        finishedNormally: false,
        iterationsCompleted: 0,
      ));

      await OrphanRecovery.sweep(sessions);

      final back = (await sessions.getById('empty'))!;
      expect(back.endedAt, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(back.finishedNormally, isFalse);
    });

    test('ignores already-closed sessions', () async {
      await sessions.insert(SessionRecord(
        id: 'closed',
        shooterId: 'sh',
        programType: 'A',
        configJson: '{}',
        configHash: 'h',
        startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        endedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        finishedNormally: true,
        iterationsCompleted: 3,
      ));
      final count = await OrphanRecovery.sweep(sessions);
      expect(count, 0);
      final back = (await sessions.getById('closed'))!;
      expect(back.finishedNormally, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/orphan_recovery_test.dart`
Expected: FAIL — `OrphanRecovery` not defined.

- [ ] **Step 3: Implement OrphanRecovery**

```dart
// lib/services/orphan_recovery.dart
//
// On app startup, any session row with ended_at IS NULL was left open by a
// crash / kill / disconnect. Close each one using the last event timestamp
// (or started_at if no events), and mark finished_normally=0.

import '../repositories/session_repository.dart';

class OrphanRecovery {
  /// Returns the number of sessions closed.
  static Future<int> sweep(SessionRepository sessions) async {
    final orphans = await sessions.findOrphanSessions();
    var closed = 0;
    for (final s in orphans) {
      final last = await sessions.lastEventTimestamp(s.id);
      await sessions.closeSession(
        id: s.id,
        endedAt: last ?? s.startedAt,
        finishedNormally: false,
        iterationsCompleted: s.iterationsCompleted,
      );
      closed++;
    }
    return closed;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/orphan_recovery_test.dart`
Expected: PASS (all 3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/orphan_recovery.dart test/services/orphan_recovery_test.dart
git commit -m "feat(persistence): OrphanRecovery.sweep closes sessions left open by prior crashes"
```

---

## Task 13: ShooterState (current-shooter provider)

**Files:**
- Create: `lib/state/shooter_state.dart`
- Create: `test/state/shooter_state_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/state/shooter_state_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/constants.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import 'package:atriarch/state/shooter_state.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() => initializeTestDatabase());

  group('ShooterState', () {
    late Database db;
    late ShooterRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await DatabaseHelper.openForTesting();
      repo = ShooterRepository(db);
    });

    tearDown(() => db.close());

    test('initialize() with no saved id defaults to Unassigned', () async {
      final state = ShooterState(repo);
      await state.initialize();
      expect(state.current!.id, kUnassignedShooterId);
    });

    test('initialize() loads saved shooter id from preferences', () async {
      await repo.insert(Shooter(
        id: 'jeremy',
        displayName: 'Jeremy',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ));
      SharedPreferences.setMockInitialValues(
        {kPrefsLastShooterIdKey: 'jeremy'},
      );
      final state = ShooterState(repo);
      await state.initialize();
      expect(state.current!.id, 'jeremy');
    });

    test('selectShooter persists id and notifies listeners', () async {
      await repo.insert(Shooter(
        id: 'x',
        displayName: 'X',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ));
      final state = ShooterState(repo);
      await state.initialize();
      var notified = 0;
      state.addListener(() => notified++);

      await state.selectShooter('x');

      expect(state.current!.id, 'x');
      expect(notified, greaterThanOrEqualTo(1));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPrefsLastShooterIdKey), 'x');
    });

    test('selectShooter throws for unknown id', () async {
      final state = ShooterState(repo);
      await state.initialize();
      expect(
        () => state.selectShooter('ghost'),
        throwsA(isA<StateError>()),
      );
    });

    test('if saved id no longer exists, falls back to Unassigned', () async {
      SharedPreferences.setMockInitialValues(
        {kPrefsLastShooterIdKey: 'deleted-shooter'},
      );
      final state = ShooterState(repo);
      await state.initialize();
      expect(state.current!.id, kUnassignedShooterId);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state/shooter_state_test.dart`
Expected: FAIL — `ShooterState` not defined.

- [ ] **Step 3: Implement ShooterState**

```dart
// lib/state/shooter_state.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../models/shooter.dart';
import '../repositories/shooter_repository.dart';

class ShooterState extends ChangeNotifier {
  final ShooterRepository _repo;
  Shooter? _current;

  ShooterState(this._repo);

  Shooter? get current => _current;

  /// Load last-selected shooter from prefs, or fall back to Unassigned.
  /// Call once after DB is open.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(kPrefsLastShooterIdKey);
    if (savedId != null) {
      final saved = await _repo.getById(savedId);
      if (saved != null) {
        _current = saved;
        notifyListeners();
        return;
      }
      // Saved id no longer exists — fall through to Unassigned.
      await prefs.remove(kPrefsLastShooterIdKey);
    }
    _current = await _repo.getById(kUnassignedShooterId);
    notifyListeners();
  }

  Future<void> selectShooter(String id) async {
    final s = await _repo.getById(id);
    if (s == null) {
      throw StateError('No shooter with id $id');
    }
    _current = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefsLastShooterIdKey, id);
    notifyListeners();
  }

  /// Refresh the cached current shooter (e.g., after editing name/email).
  Future<void> refresh() async {
    final id = _current?.id;
    if (id == null) return;
    _current = await _repo.getById(id);
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/state/shooter_state_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/state/shooter_state.dart test/state/shooter_state_test.dart
git commit -m "feat(persistence): ShooterState tracks current shooter, persists across launches"
```

---

## Task 14: ShooterChip widget

**Files:**
- Create: `lib/widgets/shooter_chip.dart`
- Create: `test/widgets/shooter_chip_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
// test/widgets/shooter_chip_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import 'package:atriarch/state/shooter_state.dart';
import 'package:atriarch/widgets/shooter_chip.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() => initializeTestDatabase());

  testWidgets('renders current shooter name', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = await DatabaseHelper.openForTesting();
    final repo = ShooterRepository(db);
    await repo.insert(Shooter(
      id: 'j',
      displayName: 'Jeremy',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    ));
    final state = ShooterState(repo);
    await state.initialize();
    await state.selectShooter('j');

    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(
        value: state,
        child: Scaffold(
          appBar: AppBar(
            actions: [ShooterChip(onTap: () => tapped = true)],
          ),
        ),
      ),
    ));

    expect(find.text('Firing as: Jeremy'), findsOneWidget);

    await tester.tap(find.byType(ShooterChip));
    await tester.pump();
    expect(tapped, isTrue);

    await db.close();
  });

  testWidgets('renders Unassigned state when no shooter selected', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = await DatabaseHelper.openForTesting();
    final state = ShooterState(ShooterRepository(db));
    await state.initialize();  // defaults to Unassigned

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(
        value: state,
        child: Scaffold(
          appBar: AppBar(actions: [ShooterChip(onTap: () {})]),
        ),
      ),
    ));

    expect(find.text('Firing as: Unassigned'), findsOneWidget);
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/shooter_chip_test.dart`
Expected: FAIL — `ShooterChip` not defined.

- [ ] **Step 3: Implement ShooterChip**

```dart
// lib/widgets/shooter_chip.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/shooter_state.dart';

class ShooterChip extends StatelessWidget {
  final VoidCallback onTap;
  const ShooterChip({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = context.select<ShooterState, String>(
      (s) => s.current?.displayName ?? 'Unassigned',
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ActionChip(
        avatar: const Icon(Icons.person_outline, size: 18),
        label: Text('Firing as: $name'),
        onPressed: onTap,
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/shooter_chip_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/shooter_chip.dart test/widgets/shooter_chip_test.dart
git commit -m "feat(persistence): ShooterChip widget shows current shooter, taps to picker"
```

---

## Task 15: ShooterPickerScreen (modal)

**Files:**
- Create: `lib/screens/shooter_picker_screen.dart`
- Create: `test/screens/shooter_picker_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
// test/screens/shooter_picker_screen_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import 'package:atriarch/screens/shooter_picker_screen.dart';
import 'package:atriarch/state/shooter_state.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() => initializeTestDatabase());

  Future<Widget> makeApp(Database db) async {
    final repo = ShooterRepository(db);
    final state = ShooterState(repo);
    await state.initialize();
    return MaterialApp(
      home: MultiProvider(
        providers: [
          Provider<ShooterRepository>.value(value: repo),
          ChangeNotifierProvider<ShooterState>.value(value: state),
        ],
        child: const ShooterPickerScreen(),
      ),
    );
  }

  testWidgets('lists existing shooters and Unassigned', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = await DatabaseHelper.openForTesting();
    final repo = ShooterRepository(db);
    await repo.insert(Shooter(
      id: 'j',
      displayName: 'Jeremy',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    ));

    await tester.pumpWidget(await makeApp(db));
    await tester.pumpAndSettle();

    expect(find.text('Jeremy'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.text('+ Add shooter'), findsOneWidget);
    await db.close();
  });

  testWidgets('tapping a shooter selects it and pops', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = await DatabaseHelper.openForTesting();
    final repo = ShooterRepository(db);
    await repo.insert(Shooter(
      id: 'j',
      displayName: 'Jeremy',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    ));
    final state = ShooterState(repo);
    await state.initialize();

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => MultiProvider(
                      providers: [
                        Provider<ShooterRepository>.value(value: repo),
                        ChangeNotifierProvider<ShooterState>.value(value: state),
                      ],
                      child: const ShooterPickerScreen(),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        );
      }),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jeremy'));
    await tester.pumpAndSettle();

    expect(state.current!.id, 'j');
    expect(find.text('Open'), findsOneWidget);  // popped back
    await db.close();
  });

  testWidgets('+ Add shooter opens form and creates shooter', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = await DatabaseHelper.openForTesting();

    await tester.pumpWidget(await makeApp(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('+ Add shooter'));
    await tester.pumpAndSettle();

    expect(find.text('Add shooter'), findsOneWidget);  // form title
    expect(find.byType(TextField), findsWidgets);

    await tester.enterText(
      find.widgetWithText(TextField, 'Display name'),
      'New Shooter',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final all = await ShooterRepository(db).listAll();
    expect(all.any((s) => s.displayName == 'New Shooter'), isTrue);
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/shooter_picker_screen_test.dart`
Expected: FAIL — `ShooterPickerScreen` not defined.

- [ ] **Step 3: Implement ShooterPickerScreen**

```dart
// lib/screens/shooter_picker_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../constants.dart';
import '../models/shooter.dart';
import '../repositories/shooter_repository.dart';
import '../services/contact_validator.dart';
import '../state/shooter_state.dart';

class ShooterPickerScreen extends StatefulWidget {
  const ShooterPickerScreen({super.key});

  @override
  State<ShooterPickerScreen> createState() => _ShooterPickerScreenState();
}

class _ShooterPickerScreenState extends State<ShooterPickerScreen> {
  late Future<List<Shooter>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final repo = context.read<ShooterRepository>();
    _future = repo.listAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select shooter')),
      body: FutureBuilder<List<Shooter>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final shooters = snap.data!;
          return ListView(
            children: [
              for (final s in shooters)
                ListTile(
                  leading: Icon(
                    s.id == kUnassignedShooterId
                        ? Icons.person_off_outlined
                        : Icons.person_outline,
                  ),
                  title: Text(s.displayName),
                  onTap: () async {
                    await context.read<ShooterState>().selectShooter(s.id);
                    if (mounted) Navigator.pop(context);
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('+ Add shooter'),
                onTap: () async {
                  final created = await Navigator.push<Shooter?>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MultiProvider(
                        providers: [
                          Provider<ShooterRepository>.value(
                            value: context.read<ShooterRepository>(),
                          ),
                        ],
                        child: const _AddShooterForm(),
                      ),
                    ),
                  );
                  if (created != null && mounted) {
                    await context.read<ShooterState>().selectShooter(created.id);
                    if (mounted) Navigator.pop(context);
                  } else if (mounted) {
                    setState(_reload);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AddShooterForm extends StatefulWidget {
  const _AddShooterForm();

  @override
  State<_AddShooterForm> createState() => _AddShooterFormState();
}

class _AddShooterFormState extends State<_AddShooterForm> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _linkOpen = false;
  String? _emailWarning;
  String? _phoneWarning;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final rawEmail = _emailCtrl.text.trim();
    final rawPhone = _phoneCtrl.text.trim();
    String? savedEmail;
    String? savedPhone;

    if (rawEmail.isNotEmpty) {
      savedEmail = rawEmail;
      if (!ContactValidator.isValidEmail(rawEmail)) {
        setState(() => _emailWarning =
            'Email format looks wrong — saved anyway. Edit later if needed.');
      }
    }
    if (rawPhone.isNotEmpty) {
      final normalized = ContactValidator.normalizePhone(rawPhone);
      if (normalized != null) {
        savedPhone = normalized;
      } else {
        savedPhone = rawPhone;
        setState(() => _phoneWarning =
            'Phone format unrecognized — saved as-is. Edit later if needed.');
      }
    }

    final s = Shooter(
      id: const Uuid().v4(),
      displayName: name,
      contactEmail: savedEmail,
      contactPhone: savedPhone,
      createdAt: DateTime.now(),
    );
    await context.read<ShooterRepository>().insert(s);
    if (mounted) Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add shooter')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Display name',
                hintText: 'e.g. Jeremy',
              ),
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              initiallyExpanded: _linkOpen,
              onExpansionChanged: (v) => setState(() => _linkOpen = v),
              title: const Text('Link for later (optional)'),
              subtitle: const Text(
                'Enter your email or phone and your training data will '
                'automatically sync when you get your own Atriarch or '
                'sign in to Range Buddy.',
              ),
              children: [
                TextField(
                  controller: _emailCtrl,
                  decoration: InputDecoration(
                    labelText: 'Email (optional)',
                    errorText: _emailWarning,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneCtrl,
                  decoration: InputDecoration(
                    labelText: 'Phone (optional)',
                    errorText: _phoneWarning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/shooter_picker_screen_test.dart`
Expected: PASS (all 3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/screens/shooter_picker_screen.dart test/screens/shooter_picker_screen_test.dart
git commit -m "feat(persistence): ShooterPickerScreen with Add form and optional email/phone"
```

---

## Task 16: Wire AppState to persist drills + boot app

**Files:**
- Modify: `lib/state/app_state.dart`
- Modify: `lib/main.dart`
- Modify: `lib/screens/program_a_setup_screen.dart`
- Modify: `lib/screens/program_b_setup_screen.dart`
- Create: `test/integration/drill_persistence_test.dart`

- [ ] **Step 1: Write the integration test**

```dart
// test/integration/drill_persistence_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/models/shooter.dart';
import 'package:atriarch/repositories/session_repository.dart';
import 'package:atriarch/repositories/shooter_repository.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/state/shooter_state.dart';
import '../test_helpers/test_database.dart';

void main() {
  setUpAll(() => initializeTestDatabase());

  group('AppState persistence integration', () {
    late Database db;
    late ShooterRepository shooters;
    late SessionRepository sessions;
    late ShooterState shooterState;

    setUp(() async {
      db = await DatabaseHelper.openForTesting();
      shooters = ShooterRepository(db);
      sessions = SessionRepository(db);
      await shooters.insert(Shooter(
        id: 'j',
        displayName: 'Jeremy',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ));
      shooterState = ShooterState(shooters);
      await shooterState.initialize();
      await shooterState.selectShooter('j');
    });

    tearDown(() => db.close());

    test('startDrill creates a session row under the current shooter', () async {
      final appState = AppState.forTesting(
        sessions: sessions,
        shooterState: shooterState,
      );
      final config = DrillConfig(programType: ProgramType.programA);
      await appState.startDrill(config);

      final rows = await db.query('sessions');
      expect(rows, hasLength(1));
      expect(rows.first['shooter_id'], 'j');
      expect(rows.first['program_type'], 'A');
      expect(rows.first['ended_at'], isNull);
    });

    test('events received during drill are persisted after flush', () async {
      final appState = AppState.forTesting(
        sessions: sessions,
        shooterState: shooterState,
      );
      await appState.startDrill(DrillConfig(programType: ProgramType.programA));

      appState.handleSessionEventForTesting(
        SessionEvent(type: EventType.targetActivated, targetId: 1),
      );
      appState.handleSessionEventForTesting(
        SessionEvent(type: EventType.hitDetected, targetId: 1, hitNumber: 1, requiredHits: 1),
      );
      await appState.forceFlushForTesting();

      final evts = await db.query('session_events');
      expect(evts, hasLength(2));
    });

    test('FIN event closes session with finished_normally=1', () async {
      final appState = AppState.forTesting(
        sessions: sessions,
        shooterState: shooterState,
      );
      await appState.startDrill(DrillConfig(programType: ProgramType.programA));
      appState.handleSessionEventForTesting(
        SessionEvent(type: EventType.drillFinished),
      );
      await appState.forceFlushForTesting();

      final rows = await db.query('sessions');
      expect(rows.first['ended_at'], isNotNull);
      expect(rows.first['finished_normally'], 1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/integration/drill_persistence_test.dart`
Expected: FAIL — `AppState.forTesting`, `handleSessionEventForTesting`, `forceFlushForTesting` not defined; `startDrill` doesn't persist.

- [ ] **Step 3: Add persistence hooks to AppState**

Modify `lib/state/app_state.dart` to accept optional `SessionRepository` and `ShooterState` injections and mirror events to DB. Add the full changes below — edits at top of file for imports, then inside the class.

Add these imports to the existing import list at the top:
```dart
import 'package:uuid/uuid.dart';
import '../models/session_record.dart';
import '../repositories/session_repository.dart';
import '../services/config_hasher.dart';
import '../services/event_batcher.dart';
import 'shooter_state.dart';
```

Add these fields inside the `AppState` class (after the existing field declarations, above the constructor):
```dart
  SessionRepository? _sessions;
  ShooterState? _shooterState;
  EventBatcher? _batcher;
  String? _activeDbSessionId;
  int _iterationsCompleted = 0;
```

Replace the existing constructor with a factory+named-constructor pair:
```dart
  AppState._internal({
    SessionRepository? sessions,
    ShooterState? shooterState,
  })  : _sessions = sessions,
        _shooterState = shooterState {
    _dataSub = bleService.incomingData.listen(_handleIncomingData);
    _statusSub = bleService.connectionStatus.listen(_handleConnectionStatus);
  }

  factory AppState({
    SessionRepository? sessions,
    ShooterState? shooterState,
  }) =>
      AppState._internal(sessions: sessions, shooterState: shooterState);

  @visibleForTesting
  factory AppState.forTesting({
    required SessionRepository sessions,
    required ShooterState shooterState,
  }) =>
      AppState._internal(sessions: sessions, shooterState: shooterState);
```

Replace `startDrill` with the persistence-aware version:
```dart
  Future<void> startDrill(DrillConfig config) async {
    currentSession = DrillSession(config: config);
    unreachableTargets.clear();
    _iterationsCompleted = 0;
    _setPhase(DrillPhase.arming);

    // Persist session row + prime event batcher.
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

    await bleService.write(TransmitterProtocol.encodeDrillStart(config));
  }
```

Add event-mirroring to `_handleIncomingData`'s `SessionEvent` branch. Find this existing block:
```dart
    if (decoded is SessionEvent) {
      // First ACT/ during arming unblocks the START button -> running.
      if (decoded.type == EventType.targetActivated &&
          _phase == DrillPhase.arming) {
        _armingTimeout?.cancel();
        _armingTimeout = null;
        _setPhase(DrillPhase.running);
      }
      if (currentSession != null) {
        currentSession!.addEvent(decoded);
        if (decoded.type == EventType.drillFinished) {
          _armingTimeout?.cancel();
          _stoppingTimeout?.cancel();
          _setPhase(DrillPhase.finished);
        }
        notifyListeners();
      }
    }
```

Replace it with:
```dart
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
```

Update the `StopAck` branch — replace:
```dart
    if (decoded is StopAck) {
      _stoppingTimeout?.cancel();
      _stoppingTimeout = null;
      // Mark the session finished locally (mirrors FIN/ semantics).
      final session = currentSession;
      if (session != null && session.isRunning) {
        session.addEvent(SessionEvent(type: EventType.drillFinished));
      }
      _setPhase(DrillPhase.finished);
      return;
    }
```

with:
```dart
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
```

Add these private helpers inside `AppState` (above `dispose()`):
```dart
  Future<void> _closeActiveDbSession({required bool finishedNormally}) async {
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
        unawaited(_closeActiveDbSession(finishedNormally: true));
      }
    }
  }

  @visibleForTesting
  Future<void> forceFlushForTesting() async {
    await _batcher?.stop();
    // Recreate a fresh batcher so subsequent events are still captured.
    final id = _activeDbSessionId;
    final sessions = _sessions;
    if (id != null && sessions != null && _batcher != null) {
      _batcher = EventBatcher(
        onFlush: (events) => sessions.appendEvents(id, events),
      )..start();
    }
  }
```

Update the existing `forceDrillFinished` method to also close the DB session — add this line after `_setPhase(DrillPhase.finished);`:
```dart
    unawaited(_closeActiveDbSession(finishedNormally: false));
```

And the `stopDrill` timeout branch — in the Timer callback, after `_setPhase(DrillPhase.finished);`, add:
```dart
          unawaited(_closeActiveDbSession(finishedNormally: false));
```

Add `import 'package:flutter/foundation.dart' show visibleForTesting;` to the existing import list if it's not already there (it already has `foundation.dart` imported with `ChangeNotifier`, so just ensure `visibleForTesting` is reachable).

- [ ] **Step 4: Run the integration test to verify it passes**

Run: `flutter test test/integration/drill_persistence_test.dart`
Expected: PASS (all 3 tests).

- [ ] **Step 5: Run all existing AppState-dependent tests to verify no regression**

Run: `flutter test`
Expected: PASS. If any prior tests fail due to AppState now taking optional injections, they should still work since defaults are null (non-persisting behavior matches old behavior).

- [ ] **Step 6: Wire DB bootstrap + providers in `main.dart`**

Replace the existing `main()` function in `lib/main.dart` with:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await DatabaseHelper.instance();
  final shooterRepo = ShooterRepository(db);
  final sessionRepo = SessionRepository(db);
  // Recover any sessions left open by a prior crash.
  await OrphanRecovery.sweep(sessionRepo);

  final shooterState = ShooterState(shooterRepo);
  await shooterState.initialize();

  runApp(
    MultiProvider(
      providers: [
        Provider<ShooterRepository>.value(value: shooterRepo),
        Provider<SessionRepository>.value(value: sessionRepo),
        ChangeNotifierProvider<ShooterState>.value(value: shooterState),
        ChangeNotifierProvider<AppState>(
          create: (_) => AppState(
            sessions: sessionRepo,
            shooterState: shooterState,
          ),
        ),
      ],
      child: const AtriarchApp(),
    ),
  );
}
```

And add these imports at the top of `main.dart`:
```dart
import 'db/database_helper.dart';
import 'repositories/session_repository.dart';
import 'repositories/shooter_repository.dart';
import 'services/orphan_recovery.dart';
import 'state/shooter_state.dart';
```

Remove the now-unused single `ChangeNotifierProvider` import/wrapper — `MultiProvider` replaces it.

- [ ] **Step 7: Add ShooterChip to Program A setup screen**

Open `lib/screens/program_a_setup_screen.dart`. Find the `AppBar` widget in the build method and add `actions:` containing the ShooterChip that opens the picker. Add at the top of the file:

```dart
import '../widgets/shooter_chip.dart';
import 'shooter_picker_screen.dart';
```

In the build method, locate the `AppBar(...)` and update it (example — adapt to the actual existing AppBar):
```dart
  AppBar(
    title: const Text('Program A'),
    actions: [
      ShooterChip(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ShooterPickerScreen(),
          ),
        ),
      ),
    ],
  ),
```

If the existing AppBar already has `actions:`, prepend `ShooterChip(...)` to the list.

- [ ] **Step 8: Add ShooterChip to Program B setup screen**

Repeat Step 7 for `lib/screens/program_b_setup_screen.dart` — same imports, same AppBar actions addition.

- [ ] **Step 9: Run the full test suite**

Run: `flutter test`
Expected: all tests PASS.

- [ ] **Step 10: Manually smoke-test the app**

Run: `flutter run -d chrome` (or on your connected device)
Expected behaviors:
- App launches without errors; DB file is created at the app's documents dir (check via `flutter run` logs if a sqflite debug log is emitted).
- Program A / B setup screens show a "Firing as: Unassigned" chip in the app bar.
- Tapping the chip opens the picker; "Unassigned" is listed; "+ Add shooter" works.
- Adding a shooter lets you enter optional email/phone under the collapsible "Link for later" section.
- After firing a drill (with real hardware or via web-kIsWeb Home flow): inspect the DB; a row should exist in `sessions` and events in `session_events`.

- [ ] **Step 11: Commit**

```bash
git add lib/state/app_state.dart lib/main.dart lib/screens/program_a_setup_screen.dart lib/screens/program_b_setup_screen.dart test/integration/drill_persistence_test.dart
git commit -m "feat(persistence): persist drills to SQLite under current shooter + orphan recovery"
```

---

## Plan Self-Review — Findings

All spec items covered by Plan 1 scope:
- ✅ Section 2 (data model): all six tables + indexes + seed Unassigned — Tasks 3, 4
- ✅ Section 4.1 (Shooter Picker): modal + Add form + optional email/phone + validator warnings — Tasks 6, 15; integrated in Task 16
- ✅ Section 5 (storage & migration): SQLite setup, event batching on 500ms cadence, `config_hash` — Tasks 4, 8, 11
- ✅ Section 6 (error handling): orphan recovery sweep, Unassigned fallback, invalid email/phone saved with warning — Tasks 12, 13, 15
- ✅ Range Buddy integration prep: UUID-keyed shooters, optional email/phone, `range_buddy_user_id` column — Tasks 3, 5, 7

Explicitly deferred to later plans (not gaps):
- MetricsEngine + session_metrics population → Plan 2
- target_engagements population → Plan 2
- Enhanced Results screen → Plan 2
- History / Trends / Analytics / Templates / Export → Plans 3, 4

Type consistency check:
- `Shooter`, `SessionRecord`, `SessionEvent`, `EventType`, `DrillConfig`, `ConfigHasher`, `EventBatcher`, `OrphanRecovery`, `ShooterRepository`, `SessionRepository`, `ShooterState`, `ContactValidator`, `ShooterChip`, `ShooterPickerScreen` — all names match across tasks.
- `kDatabaseFileName`, `kDatabaseVersion`, `kMetricsVersion`, `kUnassignedShooterId`, `kUnassignedShooterName`, `kEventBatchFlushInterval`, `kPrefsLastShooterIdKey` — consistent.
- `AppState.forTesting`, `handleSessionEventForTesting`, `forceFlushForTesting` — defined in Task 16 implementation and used in Task 16 test.

Placeholder scan: no TBD/TODO/handwaves. Every code block is concrete.

---

## Definition of Done (Plan 1)

1. `flutter test` passes all suites including new ones.
2. App launches on `chrome`/physical device without errors.
3. DB file is created; Unassigned shooter row exists on first launch.
4. Shooter Picker allows creating named shooters with optional email/phone; invalid formats warn but save.
5. Firing a drill (with real hardware) produces one `sessions` row and events in `session_events`; `FIN` → `finished_normally=1`; STOP/disconnect → `finished_normally=0`.
6. Simulating a crash (kill app mid-drill) and relaunching → orphan recovery closes the session cleanly on next boot.
7. No metrics/history UI visible yet (correct — scoped to Plans 2–4).
