import 'package:hive/hive.dart';

part 'session_summary.g.dart';

/// Summary of a completed drill, stored in the `session_history` box
/// (addendum §4.E). Lives only for the current session and auto-clears after
/// 8h of inactivity — [SessionRepository] owns that policy.
///
/// Durations are stored as integer milliseconds because Hive has no built-in
/// [Duration] adapter. The public [duration] getter hides this.
@HiveType(typeId: 11)
class SessionSummary extends HiveObject {
  @HiveField(0)
  final String drillId;

  @HiveField(1)
  final String presetName;

  @HiveField(2)
  final DateTime startedAt;

  @HiveField(3)
  final int durationMs;

  @HiveField(4)
  final int completions;

  @HiveField(5)
  final int violations;

  @HiveField(6)
  final int lateHits;

  @HiveField(7)
  final bool incomplete;

  @HiveField(8)
  int version;

  SessionSummary({
    required this.drillId,
    required this.presetName,
    required this.startedAt,
    required this.durationMs,
    required this.completions,
    required this.violations,
    required this.lateHits,
    this.incomplete = false,
    this.version = 1,
  });

  /// Convenience constructor accepting a [Duration]; stores it as
  /// milliseconds so Hive can serialize it without a custom adapter.
  factory SessionSummary.create({
    required String drillId,
    required String presetName,
    required DateTime startedAt,
    required Duration duration,
    required int completions,
    required int violations,
    required int lateHits,
    bool incomplete = false,
    int version = 1,
  }) {
    return SessionSummary(
      drillId: drillId,
      presetName: presetName,
      startedAt: startedAt,
      durationMs: duration.inMilliseconds,
      completions: completions,
      violations: violations,
      lateHits: lateHits,
      incomplete: incomplete,
      version: version,
    );
  }

  Duration get duration => Duration(milliseconds: durationMs);
}
