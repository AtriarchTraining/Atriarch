// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_summary.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SessionSummaryAdapter extends TypeAdapter<SessionSummary> {
  @override
  final int typeId = 11;

  @override
  SessionSummary read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SessionSummary(
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
