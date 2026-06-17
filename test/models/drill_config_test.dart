import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/target_group.dart';
import 'package:flutter_test/flutter_test.dart';

DrillConfig _make({
  ProgramType program = ProgramType.programA,
  double startMin = 1.0,
  double startMax = 3.0,
  double delayMin = 0.5,
  double delayMax = 2.0,
  int hitsMin = 1,
  int hitsMax = 3,
  List<TargetGroup>? groups,
  List<int>? targetIds,
  List<int>? noShootIds,
  int iterations = 5,
}) {
  return DrillConfig(
    programType: program,
    startMin: startMin,
    startMax: startMax,
    delayMin: delayMin,
    delayMax: delayMax,
    hitsMin: hitsMin,
    hitsMax: hitsMax,
    groups: groups ??
        [
          TargetGroup(id: 1, targetIds: [101, 102]),
          TargetGroup(id: 2, targetIds: [103]),
        ],
    targetIds: targetIds ?? [101, 102, 103],
    noShootIds: noShootIds ?? [103],
    iterations: iterations,
  );
}

void main() {
  group('DrillConfig.sameFields', () {
    test('true for structurally identical configs', () {
      expect(_make().sameFields(_make()), isTrue);
    });

    test('false when timing differs', () {
      expect(
        _make().sameFields(_make(startMin: 1.5)),
        isFalse,
      );
    });

    test('false when iterations differ', () {
      expect(
        _make().sameFields(_make(iterations: 7)),
        isFalse,
      );
    });

    test('false when targetIds differ', () {
      expect(
        _make().sameFields(_make(targetIds: [101, 102])),
        isFalse,
      );
    });

    test('false when noShootIds differ', () {
      expect(
        _make().sameFields(_make(noShootIds: [])),
        isFalse,
      );
    });

    test('false when a group\'s targetIds differ', () {
      expect(
        _make().sameFields(_make(groups: [
          TargetGroup(id: 1, targetIds: [101]),
          TargetGroup(id: 2, targetIds: [103]),
        ])),
        isFalse,
      );
    });

    test('false when program type differs', () {
      expect(
        _make(program: ProgramType.programA)
            .sameFields(_make(program: ProgramType.programB)),
        isFalse,
      );
    });
  });

  group('DrillConfig.sameTimingAndIterations', () {
    test('does not diverge when only group assignments change', () {
      final a = _make();
      final b = _make(
        groups: [TargetGroup(id: 1, targetIds: [999])],
        targetIds: [999],
        noShootIds: [],
      );
      expect(a.sameTimingAndIterations(b), isTrue);
    });

    test('diverges when a timing value changes', () {
      expect(
        _make().sameTimingAndIterations(_make(delayMin: 0.75)),
        isFalse,
      );
    });

    test('diverges when iterations change', () {
      expect(
        _make().sameTimingAndIterations(_make(iterations: 10)),
        isFalse,
      );
    });
  });

  group('DrillConfig.copyWithFields', () {
    test('preserves every untouched field', () {
      final src = _make();
      final copy = src.copyWithFields();
      expect(copy.sameFields(src), isTrue);
    });

    test('deep-copies groups so mutating the copy is safe', () {
      final src = _make();
      final copy = src.copyWithFields();
      copy.groups[0].targetIds.add(9999);
      expect(src.groups[0].targetIds, [101, 102]);
    });

    test('deep-copies targetIds + noShootIds', () {
      final src = _make();
      final copy = src.copyWithFields();
      copy.targetIds.add(9999);
      copy.noShootIds.add(9999);
      expect(src.targetIds, [101, 102, 103]);
      expect(src.noShootIds, [103]);
    });

    test('applies overrides without touching other fields', () {
      final src = _make();
      final copy = src.copyWithFields(
        startMin: 2.5,
        iterations: 11,
      );
      expect(copy.startMin, 2.5);
      expect(copy.iterations, 11);
      // Everything else matches the source.
      expect(copy.startMax, src.startMax);
      expect(copy.programType, src.programType);
    });
  });
}
