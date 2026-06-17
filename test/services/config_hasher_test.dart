import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/target_group.dart';
import 'package:atriarch/services/config_hasher.dart';

DrillConfig _mkConfigA() => DrillConfig(
      programType: ProgramType.programA,
      startMin: 1.0,
      startMax: 3.0,
      delayMin: 0.5,
      delayMax: 2.0,
      hitsMin: 1,
      hitsMax: 3,
      groups: [TargetGroup(id: 1, targetIds: [1, 2])],
      targetIds: [],
      noShootIds: [5],
      iterations: 5,
    );

void main() {
  group('ConfigHasher', () {
    test('same config produces same hash', () {
      final h1 = ConfigHasher.hash(_mkConfigA());
      final h2 = ConfigHasher.hash(_mkConfigA());
      expect(h1, h2);
    });

    test('different program_type produces different hash', () {
      final a = _mkConfigA();
      final b = _mkConfigA()..programType = ProgramType.programB;
      expect(ConfigHasher.hash(a), isNot(ConfigHasher.hash(b)));
    });

    test('different startMin produces different hash', () {
      final a = _mkConfigA();
      final b = _mkConfigA()..startMin = 2.0;
      expect(ConfigHasher.hash(a), isNot(ConfigHasher.hash(b)));
    });

    test('different iterations produces different hash', () {
      final a = _mkConfigA();
      final b = _mkConfigA()..iterations = 10;
      expect(ConfigHasher.hash(a), isNot(ConfigHasher.hash(b)));
    });

    test('hash is a 64-char sha256 hex string', () {
      final h = ConfigHasher.hash(_mkConfigA());
      expect(h, hasLength(64));
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(h), isTrue);
    });

    test('canonicalJson output is stable across calls', () {
      final a = _mkConfigA();
      final j1 = ConfigHasher.canonicalJson(a);
      final j2 = ConfigHasher.canonicalJson(a);
      expect(j1, j2);
    });
  });
}
