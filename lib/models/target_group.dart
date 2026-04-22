import 'package:hive/hive.dart';

part 'target_group.g.dart';

@HiveType(typeId: 2)
class TargetGroup extends HiveObject {
  @HiveField(0)
  final int id;

  @HiveField(1)
  String name;

  @HiveField(2)
  List<int> targetIds;

  TargetGroup({
    required this.id,
    String? name,
    List<int>? targetIds,
  })  : name = name ?? 'Group $id',
        targetIds = targetIds ?? [];

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'targetIds': List<int>.from(targetIds),
      };

  factory TargetGroup.fromJson(Map<String, dynamic> json) {
    final rawIds = json['targetIds'];
    final ids = rawIds is List
        ? rawIds.whereType<num>().map((n) => n.toInt()).toList(growable: false)
        : const <int>[];
    return TargetGroup(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String?,
      targetIds: List<int>.from(ids),
    );
  }
}
