import 'package:hive/hive.dart';
import 'target_group.dart';

part 'drill_config.g.dart';

@HiveType(typeId: 0)
enum ProgramType {
  @HiveField(0)
  programA,
  @HiveField(1)
  programB,
}

@HiveType(typeId: 1)
class DrillConfig extends HiveObject {
  @HiveField(0)
  ProgramType programType;

  @HiveField(1)
  double startMin;

  @HiveField(2)
  double startMax;

  @HiveField(3)
  double delayMin;

  @HiveField(4)
  double delayMax;

  @HiveField(5)
  int hitsMin;

  @HiveField(6)
  int hitsMax;

  @HiveField(7)
  List<TargetGroup> groups;

  @HiveField(8)
  List<int> targetIds;

  @HiveField(9)
  List<int> noShootIds;

  @HiveField(10)
  int iterations;

  /// Schema version for this record. Incremented when the shape changes and
  /// a migration closure in [openTypedBox] needs to run. v1 is the initial
  /// release; no prior version exists yet.
  @HiveField(11)
  int version;

  DrillConfig({
    required this.programType,
    this.startMin = 1.0,
    this.startMax = 3.0,
    this.delayMin = 0.5,
    this.delayMax = 2.0,
    this.hitsMin = 1,
    this.hitsMax = 3,
    List<TargetGroup>? groups,
    List<int>? targetIds,
    List<int>? noShootIds,
    this.iterations = 5,
    this.version = 1,
  })  : groups = groups ?? [],
        targetIds = targetIds ?? [],
        noShootIds = noShootIds ?? [];

  /// True when every timing + iteration field (plus programType) matches
  /// [other]. Does NOT compare group assignments — Program A presets match
  /// on timing; assignment reload is a separate check (target availability).
  ///
  /// Used by preset logic to distinguish between "user tweaked a timing
  /// value" and "user reshuffled groups" so we can reload groups only when
  /// every referenced target is online.
  bool sameTimingAndIterations(DrillConfig other) {
    return programType == other.programType &&
        startMin == other.startMin &&
        startMax == other.startMax &&
        delayMin == other.delayMin &&
        delayMax == other.delayMax &&
        hitsMin == other.hitsMin &&
        hitsMax == other.hitsMax &&
        iterations == other.iterations;
  }

  /// Full equality including groups / targetIds / noShootIds — used to decide
  /// whether a preset is "— modified" relative to a screen's live config.
  ///
  /// [TargetGroup] lacks its own `==` (it's a mutable HiveObject), so we
  /// compare groups by `(id, name, targetIds)` tuples in order.
  bool sameFields(DrillConfig other) {
    if (!sameTimingAndIterations(other)) return false;
    if (!_listEquals<int>(targetIds, other.targetIds)) return false;
    if (!_listEquals<int>(noShootIds, other.noShootIds)) return false;
    if (groups.length != other.groups.length) return false;
    for (var i = 0; i < groups.length; i++) {
      final a = groups[i];
      final b = other.groups[i];
      if (a.id != b.id) return false;
      if (a.name != b.name) return false;
      if (!_listEquals<int>(a.targetIds, b.targetIds)) return false;
    }
    return true;
  }

  /// Build a copy with the given overrides. Used to apply preset values into
  /// a screen-local working config. `groups`, `targetIds`, and `noShootIds`
  /// are deep-copied so mutating the copy doesn't leak back into the source.
  /// JSON view used by the drill log envelope (#17). Emits only the
  /// user-facing fields; Hive-internal metadata (version bump semantics)
  /// stays in [version] so a v2 shape can migrate cleanly.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'programType': programType.name,
        'startMin': startMin,
        'startMax': startMax,
        'delayMin': delayMin,
        'delayMax': delayMax,
        'hitsMin': hitsMin,
        'hitsMax': hitsMax,
        'iterations': iterations,
        'groups': groups.map((g) => g.toJson()).toList(growable: false),
        'targetIds': List<int>.from(targetIds),
        'noShootIds': List<int>.from(noShootIds),
        'version': version,
      };

  factory DrillConfig.fromJson(Map<String, dynamic> json) {
    final rawProgram = json['programType'];
    final program = ProgramType.values.firstWhere(
      (p) => p.name == rawProgram,
      orElse: () => ProgramType.programA,
    );
    final rawGroups = json['groups'];
    final groups = rawGroups is List
        ? rawGroups
            .whereType<Map>()
            .map((m) => TargetGroup.fromJson(Map<String, dynamic>.from(m)))
            .toList(growable: true)
        : <TargetGroup>[];
    final rawTargetIds = json['targetIds'];
    final targetIds = rawTargetIds is List
        ? rawTargetIds
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(growable: true)
        : <int>[];
    final rawNoShoot = json['noShootIds'];
    final noShootIds = rawNoShoot is List
        ? rawNoShoot
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(growable: true)
        : <int>[];
    return DrillConfig(
      programType: program,
      startMin: (json['startMin'] as num?)?.toDouble() ?? 1.0,
      startMax: (json['startMax'] as num?)?.toDouble() ?? 3.0,
      delayMin: (json['delayMin'] as num?)?.toDouble() ?? 0.5,
      delayMax: (json['delayMax'] as num?)?.toDouble() ?? 2.0,
      hitsMin: (json['hitsMin'] as num?)?.toInt() ?? 1,
      hitsMax: (json['hitsMax'] as num?)?.toInt() ?? 3,
      iterations: (json['iterations'] as num?)?.toInt() ?? 5,
      groups: groups,
      targetIds: targetIds,
      noShootIds: noShootIds,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  DrillConfig copyWithFields({
    ProgramType? programType,
    double? startMin,
    double? startMax,
    double? delayMin,
    double? delayMax,
    int? hitsMin,
    int? hitsMax,
    List<TargetGroup>? groups,
    List<int>? targetIds,
    List<int>? noShootIds,
    int? iterations,
    int? version,
  }) {
    return DrillConfig(
      programType: programType ?? this.programType,
      startMin: startMin ?? this.startMin,
      startMax: startMax ?? this.startMax,
      delayMin: delayMin ?? this.delayMin,
      delayMax: delayMax ?? this.delayMax,
      hitsMin: hitsMin ?? this.hitsMin,
      hitsMax: hitsMax ?? this.hitsMax,
      groups: groups != null
          ? groups
              .map((g) => TargetGroup(
                    id: g.id,
                    name: g.name,
                    targetIds: List<int>.from(g.targetIds),
                  ))
              .toList()
          : this
              .groups
              .map((g) => TargetGroup(
                    id: g.id,
                    name: g.name,
                    targetIds: List<int>.from(g.targetIds),
                  ))
              .toList(),
      targetIds: targetIds != null
          ? List<int>.from(targetIds)
          : List<int>.from(this.targetIds),
      noShootIds: noShootIds != null
          ? List<int>.from(noShootIds)
          : List<int>.from(this.noShootIds),
      iterations: iterations ?? this.iterations,
      version: version ?? this.version,
    );
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
