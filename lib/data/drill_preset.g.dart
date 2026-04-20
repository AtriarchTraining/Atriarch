// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drill_preset.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DrillPresetAdapter extends TypeAdapter<DrillPreset> {
  @override
  final int typeId = 10;

  @override
  DrillPreset read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DrillPreset(
      id: fields[0] as String,
      name: fields[1] as String,
      createdAt: fields[2] as DateTime,
      updatedAt: fields[3] as DateTime,
      config: fields[5] as DrillConfig,
      version: fields[4] as int,
    );
  }

  @override
  void write(BinaryWriter writer, DrillPreset obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.updatedAt)
      ..writeByte(4)
      ..write(obj.version)
      ..writeByte(5)
      ..write(obj.config);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrillPresetAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
