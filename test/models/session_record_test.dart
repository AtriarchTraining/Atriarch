import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/models/session_record.dart';

void main() {
  group('SessionRecord', () {
    test('round-trips toMap/fromMap with all fields', () {
      final r = SessionRecord(
        id: 'sess-uuid',
        shooterId: 'shooter-uuid',
        templateId: 'tpl-uuid',
        programType: 'A',
        configJson: '{"programType":"A"}',
        configHash: 'abc123',
        startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        endedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        finishedNormally: true,
        iterationsCompleted: 3,
      );
      final back = SessionRecord.fromMap(r.toMap());
      expect(back.id, r.id);
      expect(back.shooterId, r.shooterId);
      expect(back.templateId, r.templateId);
      expect(back.programType, r.programType);
      expect(back.configJson, r.configJson);
      expect(back.configHash, r.configHash);
      expect(back.startedAt, r.startedAt);
      expect(back.endedAt, r.endedAt);
      expect(back.finishedNormally, true);
      expect(back.iterationsCompleted, 3);
    });

    test('round-trips with null ended_at and false finished_normally', () {
      final r = SessionRecord(
        id: 'sess',
        shooterId: 'sh',
        templateId: null,
        programType: 'B',
        configJson: '{}',
        configHash: 'h',
        startedAt: DateTime.fromMillisecondsSinceEpoch(0),
        endedAt: null,
        finishedNormally: false,
        iterationsCompleted: 0,
      );
      final back = SessionRecord.fromMap(r.toMap());
      expect(back.endedAt, isNull);
      expect(back.finishedNormally, isFalse);
    });
  });
}
