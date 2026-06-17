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
