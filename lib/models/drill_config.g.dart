// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drill_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DrillConfigAdapter extends TypeAdapter<DrillConfig> {
  @override
  final int typeId = 1;

  @override
  DrillConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DrillConfig(
      programType: fields[0] as ProgramType,
      startMin: fields[1] as double,
      startMax: fields[2] as double,
      delayMin: fields[3] as double,
      delayMax: fields[4] as double,
      hitsMin: fields[5] as int,
      hitsMax: fields[6] as int,
      groups: (fields[7] as List?)?.cast<TargetGroup>(),
      targetIds: (fields[8] as List?)?.cast<int>(),
      noShootIds: (fields[9] as List?)?.cast<int>(),
      iterations: fields[10] as int,
      version: fields[11] as int,
    );
  }

  @override
  void write(BinaryWriter writer, DrillConfig obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.programType)
      ..writeByte(1)
      ..write(obj.startMin)
      ..writeByte(2)
      ..write(obj.startMax)
      ..writeByte(3)
      ..write(obj.delayMin)
      ..writeByte(4)
      ..write(obj.delayMax)
      ..writeByte(5)
      ..write(obj.hitsMin)
      ..writeByte(6)
      ..write(obj.hitsMax)
      ..writeByte(7)
      ..write(obj.groups)
      ..writeByte(8)
      ..write(obj.targetIds)
      ..writeByte(9)
      ..write(obj.noShootIds)
      ..writeByte(10)
      ..write(obj.iterations)
      ..writeByte(11)
      ..write(obj.version);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrillConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ProgramTypeAdapter extends TypeAdapter<ProgramType> {
  @override
  final int typeId = 0;

  @override
  ProgramType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ProgramType.programA;
      case 1:
        return ProgramType.programB;
      default:
        return ProgramType.programA;
    }
  }

  @override
  void write(BinaryWriter writer, ProgramType obj) {
    switch (obj) {
      case ProgramType.programA:
        writer.writeByte(0);
        break;
      case ProgramType.programB:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgramTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
