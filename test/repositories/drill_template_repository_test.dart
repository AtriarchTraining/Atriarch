import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/drill_template.dart';
import 'package:atriarch/repositories/drill_template_repository.dart';
import 'package:atriarch/services/config_hasher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DrillTemplate _tpl(String id, String name,
    {String? shooterId, int createdMs = 0}) {
  final config = DrillConfig(programType: ProgramType.programA);
  return DrillTemplate(
    id: id,
    shooterId: shooterId,
    name: name,
    programType: ProgramType.programA,
    config: config,
    configHash: ConfigHasher.hash(config),
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DrillTemplateRepository', () {
    test('insert then getById returns the template', () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = DrillTemplateRepository(db);
      final t = _tpl('a', 'Warm-up');
      await repo.insert(t);
      final got = await repo.getById('a');
      expect(got, isNotNull);
      expect(got!.name, 'Warm-up');
      expect(got.configHash, t.configHash);
      await db.close();
    });

    test('listAll returns templates sorted by name case-insensitive',
        () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = DrillTemplateRepository(db);
      await repo.insert(_tpl('a', 'zebra'));
      await repo.insert(_tpl('b', 'Apple'));
      await repo.insert(_tpl('c', 'mango'));
      final all = await repo.listAll();
      expect(all.map((t) => t.name).toList(), ['Apple', 'mango', 'zebra']);
      await db.close();
    });

    test('upsert replaces an existing template with the same id', () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = DrillTemplateRepository(db);
      await repo.upsert(_tpl('a', 'v1'));
      await repo.upsert(_tpl('a', 'v2'));
      expect((await repo.getById('a'))!.name, 'v2');
      expect((await repo.listAll()).length, 1);
      await db.close();
    });

    test('delete removes the row', () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = DrillTemplateRepository(db);
      await repo.insert(_tpl('a', 'X'));
      await repo.delete('a');
      expect(await repo.getById('a'), isNull);
      await db.close();
    });
  });
}
