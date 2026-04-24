// lib/screens/recent_drills_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/computed_metrics.dart';
import '../models/session_record.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import 'session_detail_screen.dart';

class RecentDrillsScreen extends StatefulWidget {
  const RecentDrillsScreen({super.key});

  @override
  State<RecentDrillsScreen> createState() => _RecentDrillsScreenState();
}

class _RecentDrillsScreenState extends State<RecentDrillsScreen> {
  Future<List<_SessionItem>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _loadItems();
  }

  Future<List<_SessionItem>> _loadItems() async {
    final state = context.read<AppState>();
    final sessionRepo = state.sessions;
    final metricsRepo = state.metricsRepo;
    if (sessionRepo == null) return const [];
    final sessions = await sessionRepo.listSessions(limit: 50);
    if (sessions.isEmpty) return const [];
    final metrics = await Future.wait(
      sessions.map((s) => metricsRepo?.getForSession(s.id) ?? Future.value(null)),
    );
    return List.generate(
      sessions.length,
      (i) => _SessionItem(sessions[i], metrics[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalScaffold(
      title: 'SESSION_HISTORY',
      body: FutureBuilder<List<_SessionItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AtriarchSpacing.lg),
                child: Text(
                  'NO SESSIONS RECORDED YET.',
                  style: AtriarchText.labelTiny(color: tokens.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AtriarchSpacing.lg),
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AtriarchSpacing.sm),
            itemBuilder: (_, i) => _SessionRow(item: items[i]),
          );
        },
      ),
    );
  }
}

class _SessionItem {
  final SessionRecord session;
  final ComputedMetrics? metrics;
  const _SessionItem(this.session, this.metrics);
}

class _SessionRow extends StatelessWidget {
  final _SessionItem item;
  const _SessionRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final session = item.session;
    final metrics = item.metrics;
    final statusColor =
        session.finishedNormally ? tokens.statusLive : tokens.statusLate;
    final statusLabel = session.finishedNormally ? 'FIN' : 'INCOMPLETE';

    return TacticalCard(
      accent: statusColor,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SessionDetailScreen(sessionId: session.id),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PROGRAM_${session.programType} // '
                  '${session.id.substring(0, 8).toUpperCase()}',
                  style: AtriarchText.labelTiny(color: tokens.statusHit),
                ),
                const SizedBox(height: 4),
                Text(
                  _fmtDateTime(session.startedAt),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                _MetricsSummaryRow(metrics: metrics, tokens: tokens),
              ],
            ),
          ),
          const SizedBox(width: AtriarchSpacing.sm),
          Text(
            statusLabel,
            style: AtriarchText.labelTiny(color: statusColor),
          ),
        ],
      ),
    );
  }

  String _fmtDateTime(DateTime t) {
    final date =
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}

class _MetricsSummaryRow extends StatelessWidget {
  final ComputedMetrics? metrics;
  final AtriarchTokens tokens;
  const _MetricsSummaryRow({required this.metrics, required this.tokens});

  @override
  Widget build(BuildContext context) {
    if (metrics == null) {
      return Text(
        'no metrics',
        style: AtriarchText.labelTiny(color: tokens.textTertiary),
      );
    }
    final m = metrics!;
    return Row(
      children: [
        _kv('DRW', m.drawMs != null ? '${m.drawMs}MS' : '--', tokens),
        const SizedBox(width: AtriarchSpacing.md),
        _kv('RXN', m.avgReactionMs != null ? '${m.avgReactionMs}MS' : '--', tokens),
        const SizedBox(width: AtriarchSpacing.md),
        _kv('RND', '${m.totalRoundsFired}', tokens),
      ],
    );
  }

  Widget _kv(String label, String value, AtriarchTokens tokens) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: AtriarchText.labelTiny(color: tokens.textTertiary),
        ),
        Text(
          value,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 11,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
