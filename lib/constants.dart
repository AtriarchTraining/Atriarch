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
