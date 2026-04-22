import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/session_event.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_hud_tile.dart';
import '../widgets/tactical/tactical_primary_button.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';
import 'home_screen.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final session = state.currentSession;

    if (session == null) {
      return const TacticalScaffold(
        title: 'RESULTS // DOSSIER',
        body: Center(child: Text('No session data.')),
      );
    }

    final tokens = context.atriarch;
    final events = session.events;
    final activations =
        events.where((e) => e.type == EventType.targetActivated).toList();
    final completions =
        events.where((e) => e.type == EventType.targetComplete).toList();
    final noShoots =
        events.where((e) => e.type == EventType.noShootViolation).toList();
    final lateHits =
        events.where((e) => e.type == EventType.lateHit).toList();
    final hits = events.where((e) => e.type == EventType.hitDetected).toList();

    final targetIds =
        activations.map((e) => e.targetId).whereType<int>().toSet();
    final perTarget = <int, _TargetStats>{};
    for (final id in targetIds) {
      final tCompletions =
          completions.where((e) => e.targetId == id).toList();
      final avgTime = tCompletions.isNotEmpty
          ? tCompletions
                  .map((e) => e.totalTimeMs ?? 0)
                  .reduce((a, b) => a + b) /
              tCompletions.length
          : 0.0;
      perTarget[id] = _TargetStats(
        hits: hits.where((e) => e.targetId == id).length,
        completions: tCompletions.length,
        noShoots: noShoots.where((e) => e.targetId == id).length,
        lateHits: lateHits.where((e) => e.targetId == id).length,
        avgCompletionMs: avgTime,
      );
    }

    return TacticalScaffold(
      title: 'RESULTS // DOSSIER',
      body: ListView(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        children: [
          Text(
            'PROTOCOL_STATUS',
            style: AtriarchText.labelTiny(color: tokens.textTertiary),
          ),
          const SizedBox(height: 4),
          Text(
            'DRILL COMPLETE',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AtriarchSpacing.lg),
          const TacticalSection(code: 'SUMMARY_01', trailing: 'KPI'),
          const SizedBox(height: AtriarchSpacing.sm),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.4,
            mainAxisSpacing: AtriarchSpacing.sm,
            crossAxisSpacing: AtriarchSpacing.sm,
            children: [
              TacticalHudTile(
                label: 'duration',
                value: _formatDuration(session.elapsed),
              ),
              TacticalHudTile(
                label: 'activations',
                value: '${activations.length}',
              ),
              TacticalHudTile(label: 'total hits', value: '${hits.length}'),
              TacticalHudTile(
                label: 'completions',
                value: '${completions.length}',
                accent: tokens.statusLive,
              ),
              TacticalHudTile(
                label: 'no-shoot',
                value: '${noShoots.length}',
                accent: noShoots.isEmpty
                    ? tokens.statusLive
                    : tokens.statusViolation,
              ),
              TacticalHudTile(
                label: 'late hits',
                value: '${lateHits.length}',
                accent:
                    lateHits.isEmpty ? tokens.statusLive : tokens.statusLate,
              ),
            ],
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(code: 'SUMMARY_02', trailing: 'PER_NODE'),
          const SizedBox(height: AtriarchSpacing.sm),
          ...perTarget.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: AtriarchSpacing.sm),
              child: _PerTargetRow(id: entry.key, stats: entry.value),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(code: 'SUMMARY_03', trailing: 'EVENT_LOG'),
          const SizedBox(height: AtriarchSpacing.sm),
          ...events.map((e) => _EventRow(event: e)),
          const SizedBox(height: AtriarchSpacing.xl),
          TacticalPrimaryButton(
            label: 'new drill',
            icon: Icons.refresh,
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.xxl),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s}s';
  }
}

class _TargetStats {
  final int hits;
  final int completions;
  final int noShoots;
  final int lateHits;
  final double avgCompletionMs;
  _TargetStats({
    required this.hits,
    required this.completions,
    required this.noShoots,
    required this.lateHits,
    required this.avgCompletionMs,
  });
}

class _PerTargetRow extends StatelessWidget {
  final int id;
  final _TargetStats stats;
  const _PerTargetRow({required this.id, required this.stats});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalCard(
      accent: tokens.border,
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              'NODE_T$id',
              style: AtriarchText.labelTiny(color: tokens.statusHit),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _kv('HITS', '${stats.hits}', tokens),
                  _kv('DONE', '${stats.completions}', tokens),
                  _kv('AVG', '${stats.avgCompletionMs.toInt()}MS', tokens),
                  _kv(
                    'NS',
                    '${stats.noShoots}',
                    tokens,
                    color: stats.noShoots > 0
                        ? tokens.statusViolation
                        : tokens.textPrimary,
                  ),
                  _kv(
                    'LATE',
                    '${stats.lateHits}',
                    tokens,
                    color: stats.lateHits > 0
                        ? tokens.statusLate
                        : tokens.textPrimary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, AtriarchTokens tokens, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(right: AtriarchSpacing.lg),
      child: Row(
        children: [
          Text(
            '$k ',
            style: AtriarchText.labelTiny(color: tokens.textTertiary),
          ),
          Text(
            v,
            style: TextStyle(
              color: color ?? tokens.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final SessionEvent event;
  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final (color, text) = switch (event.type) {
      EventType.targetActivated => (
          tokens.statusLive,
          'Target ${event.targetId} activated',
        ),
      EventType.hitDetected => (
          tokens.statusHit,
          'Target ${event.targetId} hit ${event.hitNumber}/${event.requiredHits}',
        ),
      EventType.targetComplete => (
          tokens.statusLive,
          'Target ${event.targetId} complete (${event.totalTimeMs}ms)',
        ),
      EventType.noShootViolation => (
          tokens.statusViolation,
          'NO-SHOOT Target ${event.targetId}!',
        ),
      EventType.lateHit => (
          tokens.statusLate,
          'Late hit on Target ${event.targetId}',
        ),
      EventType.drillFinished => (tokens.textTertiary, 'Drill finished'),
      EventType.error => (
          tokens.statusViolation,
          'Error: ${event.errorDetail}',
        ),
    };
    final ts =
        '${event.timestamp.hour}:${event.timestamp.minute.toString().padLeft(2, '0')}:${event.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 2)),
      ),
      child: Row(
        children: [
          const SizedBox(width: AtriarchSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            ts,
            style: AtriarchText.labelTiny(color: tokens.textTertiary),
          ),
        ],
      ),
    );
  }
}
