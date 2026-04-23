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

  /// SQLite row map shim (alias of [toJson]).
  Map<String, Object?> toMap() => toJson().cast<String, Object?>();

  factory TargetGroup.fromMap(Map<String, Object?> m) =>
      TargetGroup.fromJson(Map<String, dynamic>.from(m));
}
