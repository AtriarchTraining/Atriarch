import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/drill_template.dart';
import 'package:atriarch/services/config_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DrillTemplate', () {
    test('toRow serializes fields into drill_templates row shape', () {
      final config = DrillConfig(programType: ProgramType.programA);
      final t = DrillTemplate(
        id: 'tpl1',
        shooterId: null,
        name: 'Warm-up',
        programType: ProgramType.programA,
        config: config,
        configHash: ConfigHasher.hash(config),
        createdAt: DateTime.fromMillisecondsSinceEpoch(1234),
      );
      final row = t.toRow();
      expect(row['id'], 'tpl1');
      expect(row['shooter_id'], isNull);
      expect(row['name'], 'Warm-up');
      expect(row['program_type'], 'A');
      expect(row['config_json'], ConfigHasher.canonicalJson(config));
      expect(row['config_hash'], ConfigHasher.hash(config));
      expect(row['created_at'], 1234);
    });

    test('fromRow round-trips through toRow', () {
      final config = DrillConfig(programType: ProgramType.programB);
      final original = DrillTemplate(
        id: 'tpl2',
        shooterId: 'shooter-x',
        name: 'Mover',
        programType: ProgramType.programB,
        config: config,
        configHash: ConfigHasher.hash(config),
        createdAt: DateTime.fromMillisecondsSinceEpoch(5678),
      );
      final round = DrillTemplate.fromRow(original.toRow());
      expect(round.id, original.id);
      expect(round.shooterId, original.shooterId);
      expect(round.name, original.name);
      expect(round.programType, original.programType);
      expect(round.configHash, original.configHash);
      expect(round.createdAt, original.createdAt);
      expect(round.config.programType, original.config.programType);
    });
  });
}
