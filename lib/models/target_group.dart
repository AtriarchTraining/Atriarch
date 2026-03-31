class TargetGroup {
  final int id;
  String name;
  List<int> targetIds;

  TargetGroup({
    required this.id,
    String? name,
    List<int>? targetIds,
  })  : name = name ?? 'Group $id',
        targetIds = targetIds ?? [];
}
