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

  group('MetricsRepository.aggregateByTarget', () {
      test('returns empty list when no engagements exist', () async {
        final db = await DatabaseHelper.openForTesting();
        final repo = MetricsRepository(db);
        final result = await repo.aggregateByTarget();
        expect(result, isEmpty);
        await db.close();
      });

      test('aggregates single target across two sessions', () async {
        final db = await DatabaseHelper.openForTesting();
        final sessionsRepo = SessionRepository(db);
        final repo = MetricsRepository(db);

        // Need FK parent rows — insert sessions first
        await sessionsRepo.insert(SessionRecord(
          id: 'sess-a',
          shooterId: kUnassignedShooterId,
          programType: 'A',
          configJson: '{}',
          configHash: 'h',
          startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
          finishedNormally: true,
          iterationsCompleted: 1,
        ));
        await sessionsRepo.insert(SessionRecord(
          id: 'sess-b',
          shooterId: kUnassignedShooterId,
          programType: 'A',
          configJson: '{}',
          configHash: 'h',
          startedAt: DateTime.fromMillisecondsSinceEpoch(2000),
          finishedNormally: true,
          iterationsCompleted: 1,
        ));

        await repo.save(ComputedMetrics(
          sessionId: 'sess-a',
          totalRoundsFired: 2,
          noShootCount: 0,
          lateHitCount: 0,
          metricsVersion: kMetricsVersion,
          engagements: const [
            TargetEngagementMetrics(
              sessionId: 'sess-a', targetId: 1, engagementIndex: 0,
              activatedAtMs: 0, precedingDelayMs: 0, reactionMs: 200,
              hitsLanded: 2, requiredHits: 2,
            ),
          ],
        ));

        await repo.save(ComputedMetrics(
          sessionId: 'sess-b',
          totalRoundsFired: 2,
          noShootCount: 1,
          lateHitCount: 0,
          metricsVersion: kMetricsVersion,
          engagements: const [
            TargetEngagementMetrics(
              sessionId: 'sess-b', targetId: 1, engagementIndex: 0,
              activatedAtMs: 0, precedingDelayMs: 0, reactionMs: 400,
              hitsLanded: 1, requiredHits: 2, wasNoShoot: true,
            ),
          ],
        ));

        final result = await repo.aggregateByTarget();
        expect(result, hasLength(1));
        final t1 = result.first;
        expect(t1.targetId, 1);
        expect(t1.avgReactionMs, 300); // (200+400)/2
        expect(t1.totalHits, 3);
        expect(t1.totalRequired, 4);
        expect(t1.noShootCount, 1);
        expect(t1.totalEngagements, 2);
        await db.close();
      });

      test('returns multiple targets sorted by avg_reaction_ms DESC', () async {
        final db = await DatabaseHelper.openForTesting();
        final sessionsRepo = SessionRepository(db);
        final repo = MetricsRepository(db);

        await sessionsRepo.insert(SessionRecord(
          id: 'sess-c',
          shooterId: kUnassignedShooterId,
          programType: 'A',
          configJson: '{}',
          configHash: 'h',
          startedAt: DateTime.fromMillisecondsSinceEpoch(3000),
          finishedNormally: true,
          iterationsCompleted: 1,
        ));

        await repo.save(ComputedMetrics(
          sessionId: 'sess-c',
          totalRoundsFired: 4,
          noShootCount: 0,
          lateHitCount: 1,
          metricsVersion: kMetricsVersion,
          engagements: const [
            TargetEngagementMetrics(
              sessionId: 'sess-c', targetId: 1, engagementIndex: 0,
              activatedAtMs: 0, precedingDelayMs: 0, reactionMs: 500,
              hitsLanded: 2, requiredHits: 2,
            ),
            TargetEngagementMetrics(
              sessionId: 'sess-c', targetId: 2, engagementIndex: 1,
              activatedAtMs: 1000, precedingDelayMs: 0, reactionMs: 250,
              hitsLanded: 2, requiredHits: 2, hadLateHit: true,
            ),
          ],
        ));

        final result = await repo.aggregateByTarget();
        expect(result, hasLength(2));
        expect(result[0].targetId, 1); // slowest first
        expect(result[1].targetId, 2);
        expect(result[1].lateHitCount, 1);
        await db.close();
      });

      test('engagements with null reaction_ms excluded from AVG', () async {
        final db = await DatabaseHelper.openForTesting();
        final sessionsRepo = SessionRepository(db);
        final repo = MetricsRepository(db);

        await sessionsRepo.insert(SessionRecord(
          id: 'sess-d',
          shooterId: kUnassignedShooterId,
          programType: 'A',
          configJson: '{}',
          configHash: 'h',
          startedAt: DateTime.fromMillisecondsSinceEpoch(4000),
          finishedNormally: false,
          iterationsCompleted: 0,
        ));

        await repo.save(ComputedMetrics(
          sessionId: 'sess-d',
          totalRoundsFired: 1,
          noShootCount: 0,
          lateHitCount: 0,
          metricsVersion: kMetricsVersion,
          engagements: const [
            TargetEngagementMetrics(
              sessionId: 'sess-d', targetId: 3, engagementIndex: 0,
              activatedAtMs: 0, precedingDelayMs: 0, reactionMs: 600,
              hitsLanded: 1, requiredHits: 1,
            ),
            TargetEngagementMetrics(
              sessionId: 'sess-d', targetId: 3, engagementIndex: 1,
              activatedAtMs: 1000, precedingDelayMs: 0, reactionMs: null,
              hitsLanded: 0, requiredHits: 1,
            ),
          ],
        ));

        final result = await repo.aggregateByTarget();
        expect(result, hasLength(1));
        expect(result.first.avgReactionMs, 600); // NULL excluded by AVG()
        expect(result.first.totalEngagements, 2);
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
