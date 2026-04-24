// test/repositories/metrics_repository_test.dart
import 'package:atriarch/constants.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/models/computed_metrics.dart';
import 'package:atriarch/models/session_record.dart';
import 'package:atriarch/repositories/metrics_repository.dart';
import 'package:atriarch/repositories/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> insertSession(SessionRepository repo, String id) async {
    await repo.insert(SessionRecord(
      id: id,
      shooterId: kUnassignedShooterId,
      programType: 'A',
      configJson: '{}',
      configHash: 'h',
      startedAt: DateTime.fromMillisecondsSinceEpoch(0),
      finishedNormally: true,
      iterationsCompleted: 1,
    ));
  }

  ComputedMetrics sampleMetrics(String sessionId) => ComputedMetrics(
        sessionId: sessionId,
        drawMs: 350,
        totalDurationMs: 5000,
        totalRoundsFired: 3,
        noShootCount: 0,
        lateHitCount: 1,
        avgReactionMs: 300,
        medianReactionMs: 290,
        stddevReactionMs: 25,
        avgSplitMs: 200,
        avgTransitionMs: 400,
        dataQualityWarning: false,
        metricsVersion: kMetricsVersion,
        engagements: const [
          TargetEngagementMetrics(
            sessionId: 'sess-1',
            targetId: 1,
            engagementIndex: 0,
            activatedAtMs: 1000,
            precedingDelayMs: 0,
            reactionMs: 300,
            hitsLanded: 2,
            requiredHits: 2,
            engagementTimeMs: 500,
          ),
        ],
      );

  group('MetricsRepository.save', () {
    test('writes session_metrics row', () async {
      final db = await DatabaseHelper.openForTesting();
      final sessions = SessionRepository(db);
      final repo = MetricsRepository(db);
      await insertSession(sessions, 'sess-1');

      await repo.save(sampleMetrics('sess-1'));

      final rows = await db.query('session_metrics',
          where: 'session_id = ?', whereArgs: ['sess-1']);
      expect(rows, hasLength(1));
      expect(rows.first['draw_ms'], 350);
      expect(rows.first['total_rounds_fired'], 3);
      expect(rows.first['avg_reaction_ms'], 300);
      await db.close();
    });

    test('writes target_engagements rows', () async {
      final db = await DatabaseHelper.openForTesting();
      final sessions = SessionRepository(db);
      final repo = MetricsRepository(db);
      await insertSession(sessions, 'sess-1');

      await repo.save(sampleMetrics('sess-1'));

      final rows = await db.query('target_engagements',
          where: 'session_id = ?', whereArgs: ['sess-1']);
      expect(rows, hasLength(1));
      expect(rows.first['target_id'], 1);
      expect(rows.first['reaction_ms'], 300);
      expect(rows.first['hits_landed'], 2);
      await db.close();
    });

    test('save is idempotent — second call replaces first', () async {
      final db = await DatabaseHelper.openForTesting();
      final sessions = SessionRepository(db);
      final repo = MetricsRepository(db);
      await insertSession(sessions, 'sess-1');

      await repo.save(sampleMetrics('sess-1'));

      final updated = ComputedMetrics(
        sessionId: 'sess-1',
        drawMs: 999,
        totalDurationMs: 1000,
        totalRoundsFired: 1,
        noShootCount: 0,
        lateHitCount: 0,
        metricsVersion: kMetricsVersion,
        engagements: const [],
      );
      await repo.save(updated);

      final rows = await db.query('session_metrics',
          where: 'session_id = ?', whereArgs: ['sess-1']);
      expect(rows, hasLength(1));
      expect(rows.first['draw_ms'], 999);
      final engRows = await db.query('target_engagements',
          where: 'session_id = ?', whereArgs: ['sess-1']);
      expect(engRows, isEmpty);
      await db.close();
    });
  });

  group('MetricsRepository.getForSession', () {
    test('returns null for unknown session', () async {
      final db = await DatabaseHelper.openForTesting();
      final repo = MetricsRepository(db);
      expect(await repo.getForSession('nope'), isNull);
      await db.close();
    });

    test('round-trips ComputedMetrics', () async {
      final db = await DatabaseHelper.openForTesting();
      final sessions = SessionRepository(db);
      final repo = MetricsRepository(db);
      await insertSession(sessions, 'sess-1');

      await repo.save(sampleMetrics('sess-1'));
      final loaded = await repo.getForSession('sess-1');

      expect(loaded, isNotNull);
      expect(loaded!.drawMs, 350);
      expect(loaded.avgReactionMs, 300);
      expect(loaded.engagements, hasLength(1));
      expect(loaded.engagements.first.reactionMs, 300);
      expect(loaded.engagements.first.hitsLanded, 2);
      await db.close();
    });
  });
}
