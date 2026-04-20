import 'package:hive/hive.dart';

/// Summary of a completed drill, stored in the `session_history` box
/// (addendum §4.E). Lives only for the current session and auto-clears after
/// 8h of inactivity — [SessionRepository] owns that policy.
///
/// Durations are stored as integer milliseconds because Hive has no built-in
/// [Duration] adapter. External callers must use [SessionSummary.create]
/// (which accepts a [Duration]) — the field-based constructor is private so
/// nobody can accidentally pass seconds where ms are expected.
///
/// The Hive adapter for this type is hand-written ([SessionSummaryAdapter])
/// instead of generated, because `hive_generator` requires a public unnamed
/// constructor and we want all external construction to go through
/// [SessionSummary.create].
class SessionSummary extends HiveObject {
  static const int hiveTypeId = 11;

  final String drillId;
  final String presetName;
  final DateTime startedAt;
  final int durationMs;
  final int completions;
  final int violations;
  final int lateHits;
  final bool incomplete;
  int version;

  /// Internal field-based constructor. External callers must use
  /// [SessionSummary.create]; only the adapter and this file's factory
  /// reach here.
  SessionSummary._fromFields({
    required this.drillId,
    required this.presetName,
    required this.startedAt,
    required this.durationMs,
    required this.completions,
    required this.violations,
    required this.lateHits,
    this.incomplete = false,
    this.version = 1,
  }) : assert(durationMs >= 0, 'durationMs must be non-negative');

  /// Canonical constructor. Stores [duration] as milliseconds so Hive can
  /// serialize it without a custom adapter for [Duration].
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
    return SessionSummary._fromFields(
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

/// Hand-written Hive adapter — see class-level doc on [SessionSummary] for
/// why this isn't generated. Field ordering mirrors the previously-generated
/// adapter so on-disk data is forwards-compatible with the v1 shape.
class SessionSummaryAdapter extends TypeAdapter<SessionSummary> {
  @override
  final int typeId = SessionSummary.hiveTypeId;

  @override
  SessionSummary read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SessionSummary._fromFields(
      drillId: fields[0] as String,
      presetName: fields[1] as String,
      startedAt: fields[2] as DateTime,
      durationMs: fields[3] as int,
      completions: fields[4] as int,
      violations: fields[5] as int,
      lateHits: fields[6] as int,
      incomplete: fields[7] as bool,
      version: fields[8] as int,
    );
  }

  @override
  void write(BinaryWriter writer, SessionSummary obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.drillId)
      ..writeByte(1)
      ..write(obj.presetName)
      ..writeByte(2)
      ..write(obj.startedAt)
      ..writeByte(3)
      ..write(obj.durationMs)
      ..writeByte(4)
      ..write(obj.completions)
      ..writeByte(5)
      ..write(obj.violations)
      ..writeByte(6)
      ..write(obj.lateHits)
      ..writeByte(7)
      ..write(obj.incomplete)
      ..writeByte(8)
      ..write(obj.version);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionSummaryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
