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
}
