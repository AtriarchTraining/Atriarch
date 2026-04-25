// test/repositories/metrics_repository_trend_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:atriarch/db/database_helper.dart';
import 'package:atriarch/repositories/metrics_repository.dart';

void main() {
  group('MetricsRepository.listRecentMetrics', () {
    late Database db;
    late MetricsRepository repo;

    setUp(() async {
      db = await DatabaseHelper.openForTesting();
      repo = MetricsRepository(db);
    });

    tearDown(() async => db.close());

    test('returns empty list when no rows', () async {
      final result = await repo.listRecentMetrics(limit: 20);
      expect(result, isEmpty);
    });

    test('returns up to limit rows, most-recent first', () async {
      for (var i = 1; i <= 3; i++) {
        // Insert shooter first
        await db.insert('shooters', {
          'id': 'shooter-$i',
          'display_name': 'Test Shooter $i',
          'contact_email': null,
          'contact_phone': null,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'range_buddy_user_id': null,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        // Insert session to satisfy foreign key
        await db.insert('sessions', {
          'id': 'sid-$i',
          'shooter_id': 'shooter-$i',
          'template_id': null,
          'program_type': 'test',
          'config_json': '{}',
          'config_hash': 'hash$i',
          'started_at': DateTime.now().millisecondsSinceEpoch,
          'ended_at': null,
          'finished_normally': 0,
          'iterations_completed': 0,
        });
        await db.insert('session_metrics', {
          'session_id': 'sid-$i',
          'draw_ms': i * 100,
          'avg_reaction_ms': i * 200,
          'avg_split_ms': i * 50,
          'avg_transition_ms': i * 75,
          'total_duration_ms': null,
          'total_rounds_fired': 10,
          'no_shoot_count': 0,
          'late_hit_count': 0,
          'median_reaction_ms': null,
          'stddev_reaction_ms': null,
          'data_quality_warning': 0,
          'metrics_version': 1,
        });
      }

      final result = await repo.listRecentMetrics(limit: 20);
      expect(result.length, 3);
      expect(result.first.sessionId, 'sid-3');
      expect(result.first.drawMs, 300);
      expect(result.first.avgReactionMs, 600);
      expect(result.first.avgSplitMs, 150);
      expect(result.first.avgTransitionMs, 225);
    });

    test('respects limit', () async {
      for (var i = 1; i <= 5; i++) {
        // Insert shooter first
        await db.insert('shooters', {
          'id': 'shooter-$i',
          'display_name': 'Test Shooter $i',
          'contact_email': null,
          'contact_phone': null,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'range_buddy_user_id': null,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        // Insert session to satisfy foreign key
        await db.insert('sessions', {
          'id': 'sid-$i',
          'shooter_id': 'shooter-$i',
          'template_id': null,
          'program_type': 'test',
          'config_json': '{}',
          'config_hash': 'hash$i',
          'started_at': DateTime.now().millisecondsSinceEpoch,
          'ended_at': null,
          'finished_normally': 0,
          'iterations_completed': 0,
        });
        await db.insert('session_metrics', {
          'session_id': 'sid-$i',
          'draw_ms': i * 100,
          'avg_reaction_ms': null,
          'avg_split_ms': null,
          'avg_transition_ms': null,
          'total_duration_ms': null,
          'total_rounds_fired': 5,
          'no_shoot_count': 0,
          'late_hit_count': 0,
          'median_reaction_ms': null,
          'stddev_reaction_ms': null,
          'data_quality_warning': 0,
          'metrics_version': 1,
        });
      }
      final result = await repo.listRecentMetrics(limit: 3);
      expect(result.length, 3);
    });

    test('nullable fields survive round-trip', () async {
      // Insert shooter first
      await db.insert('shooters', {
        'id': 'shooter-null',
        'display_name': 'Test Shooter Null',
        'contact_email': null,
        'contact_phone': null,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'range_buddy_user_id': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      // Insert session to satisfy foreign key
      await db.insert('sessions', {
        'id': 'sid-null',
        'shooter_id': 'shooter-null',
        'template_id': null,
        'program_type': 'test',
        'config_json': '{}',
        'config_hash': 'hash-null',
        'started_at': DateTime.now().millisecondsSinceEpoch,
        'ended_at': null,
        'finished_normally': 0,
        'iterations_completed': 0,
      });
      await db.insert('session_metrics', {
        'session_id': 'sid-null',
        'draw_ms': null,
        'avg_reaction_ms': null,
        'avg_split_ms': null,
        'avg_transition_ms': null,
        'total_duration_ms': null,
        'total_rounds_fired': 0,
        'no_shoot_count': 0,
        'late_hit_count': 0,
        'median_reaction_ms': null,
        'stddev_reaction_ms': null,
        'data_quality_warning': 0,
        'metrics_version': 1,
      });
      final result = await repo.listRecentMetrics(limit: 1);
      expect(result.length, 1);
      expect(result.first.drawMs, isNull);
      expect(result.first.avgReactionMs, isNull);
      expect(result.first.avgSplitMs, isNull);
      expect(result.first.avgTransitionMs, isNull);
    });
  });
}
