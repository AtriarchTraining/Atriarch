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
}
