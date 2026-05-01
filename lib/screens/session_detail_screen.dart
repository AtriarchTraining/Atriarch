// lib/screens/session_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/computed_metrics.dart';
import '../models/session_record.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../util/target_name_resolver.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_hud_tile.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';
import '../widgets/tactical/tactical_status_chip.dart';

class SessionDetailScreen extends StatefulWidget {
  final String sessionId;
  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  Future<_DetailData>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<_DetailData> _load() async {
    final state = context.read<AppState>();
    final session = await state.sessions?.getById(widget.sessionId);
    final metrics = await state.metricsRepo?.getForSession(widget.sessionId);
    return _DetailData(session, metrics);
  }

  @override
  Widget build(BuildContext context) {
    return TacticalScaffold(
      title: 'DRILL_DETAIL',
      body: FutureBuilder<_DetailData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data;
          if (data == null || data.session == null) {
            final tokens = context.atriarch;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AtriarchSpacing.lg),
                child: Text(
                  'SESSION NOT FOUND.',
                  style: AtriarchText.labelTiny(color: tokens.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _DetailBody(session: data.session!, metrics: data.metrics);
        },
      ),
    );
  }
}

class _DetailData {
  final SessionRecord? session;
  final ComputedMetrics? metrics;
  const _DetailData(this.session, this.metrics);
}

class _DetailBody extends StatelessWidget {
  final SessionRecord session;
  final ComputedMetrics? metrics;
  const _DetailBody({required this.session, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return ListView(
      padding: const EdgeInsets.all(AtriarchSpacing.lg),
      children: [
        Text(
          'PROGRAM_${session.programType}',
          style: AtriarchText.labelTiny(color: tokens.statusHit),
        ),
        const SizedBox(height: 4),
        Text(
          _fmtDateTime(session.startedAt),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AtriarchSpacing.sm),
        Row(
          children: [
            TacticalStatusChip(
              color: session.finishedNormally
                  ? tokens.statusLive
                  : tokens.statusLate,
              label: session.finishedNormally ? 'COMPLETE' : 'INCOMPLETE',
            ),
            const SizedBox(width: AtriarchSpacing.md),
            Text(
              '${session.iterationsCompleted} iter',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.textTertiary),
            ),
            if (metrics?.totalDurationMs != null) ...[
              const SizedBox(width: AtriarchSpacing.md),
              Text(
                _fmtDuration(metrics!.totalDurationMs!),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: tokens.textTertiary),
              ),
            ],
          ],
        ),
        const SizedBox(height: AtriarchSpacing.xl),

        if (metrics != null) ...[
          const TacticalSection(code: 'DETAIL_01', trailing: 'TIMING'),
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
                label: 'draw',
                value: metrics!.drawMs != null ? '${metrics!.drawMs}MS' : '--',
              ),
              TacticalHudTile(
                label: 'avg reaction',
                value: metrics!.avgReactionMs != null
                    ? '${metrics!.avgReactionMs}MS'
                    : '--',
              ),
              TacticalHudTile(
                label: 'avg split',
                value: metrics!.avgSplitMs != null
                    ? '${metrics!.avgSplitMs}MS'
                    : '--',
              ),
              TacticalHudTile(
                label: 'transition',
                value: metrics!.avgTransitionMs != null
                    ? '${metrics!.avgTransitionMs}MS'
                    : '--',
              ),
            ],
          ),
          const SizedBox(height: AtriarchSpacing.xl),

          const TacticalSection(code: 'DETAIL_02', trailing: 'TOTALS'),
          const SizedBox(height: AtriarchSpacing.sm),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.2,
            mainAxisSpacing: AtriarchSpacing.sm,
            crossAxisSpacing: AtriarchSpacing.sm,
            children: [
              TacticalHudTile(
                label: 'rounds',
                value: '${metrics!.totalRoundsFired}',
              ),
              TacticalHudTile(
                label: 'no-shoot',
                value: '${metrics!.noShootCount}',
                accent: metrics!.noShootCount > 0
                    ? tokens.statusViolation
                    : null,
              ),
              TacticalHudTile(
                label: 'late hits',
                value: '${metrics!.lateHitCount}',
                accent: metrics!.lateHitCount > 0 ? tokens.statusLate : null,
              ),
            ],
          ),
          const SizedBox(height: AtriarchSpacing.xl),

          if (metrics!.engagements.isNotEmpty) ...[
            const TacticalSection(
                code: 'DETAIL_03', trailing: 'ENGAGEMENTS'),
            const SizedBox(height: AtriarchSpacing.sm),
            ...metrics!.engagements.map(
              (e) => Padding(
                padding:
                    const EdgeInsets.only(bottom: AtriarchSpacing.sm),
                child: _EngagementRow(engagement: e),
              ),
            ),
          ],
        ] else ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: AtriarchSpacing.xl),
              child: Text(
                'METRICS NOT AVAILABLE FOR THIS SESSION.',
                style: AtriarchText.labelTiny(color: tokens.textTertiary),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],

        const SizedBox(height: AtriarchSpacing.xxl),
      ],
    );
  }

  static String _fmtDateTime(DateTime t) {
    final date =
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '$date  $time';
  }

  static String _fmtDuration(int ms) {
    final secs = ms ~/ 1000;
    final m = secs ~/ 60;
    final s = secs.remainder(60);
    return '${m}m ${s}s';
  }
}

class _EngagementRow extends StatelessWidget {
  final TargetEngagementMetrics engagement;
  const _EngagementRow({required this.engagement});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final resolver =
        TargetNameResolver(context.read<AppState>().targetNames);
    final e = engagement;
    return TacticalCard(
      accent: e.wasNoShoot ? tokens.statusViolation : tokens.border,
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              resolver.display(e.targetId),
              style: AtriarchText.labelTiny(color: tokens.statusHit),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _kv(
                    'RXN',
                    e.reactionMs != null ? '${e.reactionMs}MS' : '--',
                    tokens,
                  ),
                  _kv('HITS', '${e.hitsLanded}/${e.requiredHits}', tokens),
                  if (e.precedingDelayMs > 0)
                    _kv('DLY', '${e.precedingDelayMs}MS', tokens,
                        color: tokens.textTertiary),
                  if (e.wasNoShoot)
                    _kv('NS', '!', tokens, color: tokens.statusViolation),
                  if (e.hadLateHit)
                    _kv('LATE', '!', tokens, color: tokens.statusLate),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _kv(String label, String value, AtriarchTokens tokens,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(right: AtriarchSpacing.lg),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: AtriarchText.labelTiny(color: tokens.textTertiary),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? tokens.textPrimary,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
