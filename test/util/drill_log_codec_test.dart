import 'dart:convert';

import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/drill_session.dart';
import 'package:atriarch/models/session_event.dart';
import 'package:atriarch/models/target_group.dart';
import 'package:atriarch/util/drill_log_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DrillLogCodec', () {
    test('round-trip: sample session -> JSON -> back reproduces fields', () {
      final config = DrillConfig(
        programType: ProgramType.programA,
        startMin: 1.25,
        startMax: 3.25,
        delayMin: 0.5,
        delayMax: 2.0,
        hitsMin: 2,
        hitsMax: 4,
        iterations: 7,
        groups: [
          TargetGroup(id: 1, name: 'Left', targetIds: [1, 2]),
          TargetGroup(id: 2, name: 'Right', targetIds: [3]),
        ],
        targetIds: [1, 2, 3],
        noShootIds: [5],
      );
      final session = DrillSession(
        config: config,
        drillId: 'fixed-drill-id',
        presetName: 'Bill Drill',
        startTime: DateTime.utc(2026, 4, 20, 14, 5, 0),
      );
      session.addEvent(SessionEvent(
        type: EventType.targetActivated,
        targetId: 1,
        timestamp: DateTime.utc(2026, 4, 20, 14, 5, 1, 234),
      ));
      session.addEvent(SessionEvent(
        type: EventType.hitDetected,
        targetId: 1,
        hitNumber: 1,
        requiredHits: 2,
        timestamp: DateTime.utc(2026, 4, 20, 14, 5, 2),
      ));
      session.addEvent(SessionEvent(
        type: EventType.targetComplete,
        targetId: 1,
        totalTimeMs: 812,
        timestamp: DateTime.utc(2026, 4, 20, 14, 5, 3),
      ));
      session.addEvent(SessionEvent(
        type: EventType.drillFinished,
        timestamp: DateTime.utc(2026, 4, 20, 14, 9, 12),
      ));

      final jsonStr = DrillLogCodec.encode(
        session,
        presetName: 'Bill Drill',
        targetNames: {1: 'Flipper', 3: 'Steel L'},
      );

      // Envelope is valid JSON with version=1 and deterministic keys.
      final decodedRaw = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decodedRaw['version'], equals(1));
      expect(decodedRaw['drillId'], equals('fixed-drill-id'));
      expect(decodedRaw['targetNames'], equals({'1': 'Flipper', '3': 'Steel L'}));

      final decoded = DrillLogCodec.decode(jsonStr);
      expect(decoded.version, equals(1));
      expect(decoded.drillId, equals('fixed-drill-id'));
      expect(decoded.presetName, equals('Bill Drill'));
      expect(decoded.startedAt, equals(DateTime.utc(2026, 4, 20, 14, 5, 0)));
      expect(decoded.targetNames, equals({1: 'Flipper', 3: 'Steel L'}));

      // DrillConfig fields survive round-trip.
      expect(decoded.config.programType, equals(ProgramType.programA));
      expect(decoded.config.startMin, equals(1.25));
      expect(decoded.config.startMax, equals(3.25));
      expect(decoded.config.delayMin, equals(0.5));
      expect(decoded.config.delayMax, equals(2.0));
      expect(decoded.config.hitsMin, equals(2));
      expect(decoded.config.hitsMax, equals(4));
      expect(decoded.config.iterations, equals(7));
      expect(decoded.config.targetIds, equals([1, 2, 3]));
      expect(decoded.config.noShootIds, equals([5]));
      expect(decoded.config.groups.length, equals(2));
      expect(decoded.config.groups[0].id, equals(1));
      expect(decoded.config.groups[0].name, equals('Left'));
      expect(decoded.config.groups[0].targetIds, equals([1, 2]));
      expect(decoded.config.groups[1].targetIds, equals([3]));

      // Events preserve type, targetId, ancillary fields, and timestamp.
      expect(decoded.events.length, equals(4));
      expect(decoded.events[0].type, equals(EventType.targetActivated));
      expect(decoded.events[0].targetId, equals(1));
      expect(
        decoded.events[0].timestamp,
        equals(DateTime.utc(2026, 4, 20, 14, 5, 1, 234)),
      );
      expect(decoded.events[1].type, equals(EventType.hitDetected));
      expect(decoded.events[1].hitNumber, equals(1));
      expect(decoded.events[1].requiredHits, equals(2));
      expect(decoded.events[2].type, equals(EventType.targetComplete));
      expect(decoded.events[2].totalTimeMs, equals(812));
      expect(decoded.events[3].type, equals(EventType.drillFinished));
    });

    test('every EventType maps to a short code', () {
      for (final type in EventType.values) {
        expect(
          kEventTypeCodes.containsKey(type),
          isTrue,
          reason: 'EventType.$type missing short code',
        );
        final code = kEventTypeCodes[type]!;
        expect(eventTypeFromCode(code), equals(type));
      }
    });

    test('null presetName -> envelope stores "Custom"', () {
      final session = DrillSession(
        config: DrillConfig(programType: ProgramType.programB),
        drillId: 'd1',
        startTime: DateTime.utc(2026, 1, 1),
      );
      final jsonStr = DrillLogCodec.encode(session);
      final raw = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect((raw['preset'] as Map)['name'], equals('Custom'));
      expect(DrillLogCodec.decode(jsonStr).presetName, equals('Custom'));
    });

    test('decode tolerates unknown event type codes', () {
      final payload = jsonEncode({
        'version': 1,
        'drillId': 'd1',
        'startedAt': '2026-01-01T00:00:00.000Z',
        'preset': {
          'name': 'Custom',
          'config': DrillConfig(programType: ProgramType.programA).toJson(),
        },
        'targetNames': <String, String>{},
        'events': [
          {'t': '2026-01-01T00:00:01.000Z', 'type': 'SOMETHING_NEW'},
        ],
      });
      final decoded = DrillLogCodec.decode(payload);
      // Unknown codes fall back to error rather than throwing.
      expect(decoded.events.single.type, equals(EventType.error));
    });
  });

  group('DrillConfig.toJson/fromJson', () {
    test('Program A with groups round-trips', () {
      final cfg = DrillConfig(
        programType: ProgramType.programA,
        startMin: 0.75,
        startMax: 2.5,
        hitsMin: 3,
        hitsMax: 5,
        iterations: 10,
        groups: [
          TargetGroup(id: 1, name: 'Alpha', targetIds: [10, 11]),
          TargetGroup(id: 3, name: 'Charlie', targetIds: [20]),
        ],
        targetIds: [10, 11, 20],
      );
      final back = DrillConfig.fromJson(cfg.toJson());
      expect(back.programType, equals(ProgramType.programA));
      expect(back.startMin, equals(0.75));
      expect(back.startMax, equals(2.5));
      expect(back.hitsMin, equals(3));
      expect(back.hitsMax, equals(5));
      expect(back.iterations, equals(10));
      expect(back.groups.length, equals(2));
      expect(back.groups[0].name, equals('Alpha'));
      expect(back.groups[0].targetIds, equals([10, 11]));
      expect(back.groups[1].id, equals(3));
      expect(back.targetIds, equals([10, 11, 20]));
    });

    test('Program B with targetIds round-trips', () {
      final cfg = DrillConfig(
        programType: ProgramType.programB,
        targetIds: [7, 8, 9],
        noShootIds: [8],
      );
      final back = DrillConfig.fromJson(cfg.toJson());
      expect(back.programType, equals(ProgramType.programB));
      expect(back.targetIds, equals([7, 8, 9]));
      expect(back.noShootIds, equals([8]));
      expect(back.groups, isEmpty);
    });
  });
}
