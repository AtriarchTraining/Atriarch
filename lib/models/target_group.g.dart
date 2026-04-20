// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'target_group.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TargetGroupAdapter extends TypeAdapter<TargetGroup> {
  @override
  final int typeId = 2;

  @override
  TargetGroup read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TargetGroup(
      id: fields[0] as int,
      name: fields[1] as String?,
      targetIds: (fields[2] as List?)?.cast<int>(),
    );
  }

  @override
  void write(BinaryWriter writer, TargetGroup obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.targetIds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TargetGroupAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
