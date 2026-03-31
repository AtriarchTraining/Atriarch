import 'target_group.dart';

enum ProgramType { programA, programB }

class DrillConfig {
  ProgramType programType;
  double startMin;
  double startMax;
  double delayMin;
  double delayMax;
  int hitsMin;
  int hitsMax;
  List<TargetGroup> groups;
  List<int> targetIds;
  List<int> noShootIds;
  int iterations;

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
  })  : groups = groups ?? [],
        targetIds = targetIds ?? [],
        noShootIds = noShootIds ?? [];
}
