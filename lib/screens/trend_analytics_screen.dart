// lib/screens/trend_analytics_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../repositories/metrics_repository.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';
import '../widgets/trend/trend_metric_panel.dart';

class TrendAnalyticsScreen extends StatefulWidget {
  const TrendAnalyticsScreen({super.key});

  @override
  State<TrendAnalyticsScreen> createState() => _TrendAnalyticsScreenState();
}

class _TrendAnalyticsScreenState extends State<TrendAnalyticsScreen> {
  Future<List<MetricSnapshot>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<MetricSnapshot>> _load() async {
    final state = context.read<AppState>();
    return state.metricsRepo?.listRecentMetrics(limit: 20) ??
        Future.value(const []);
  }

  @override
  Widget build(BuildContext context) {
    return TacticalScaffold(
      title: 'TREND_ANALYTICS',
      body: FutureBuilder<List<MetricSnapshot>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final snapshots = snap.data ?? const [];
          if (snapshots.isEmpty) {
            return _EmptyState();
          }
          return _TrendBody(snapshots: snapshots);
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
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
}

class _TrendBody extends StatelessWidget {
  final List<MetricSnapshot> snapshots;
  const _TrendBody({required this.snapshots});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    // Repo returns newest-first; reverse so sparklines show oldest -> newest.
    final ordered = snapshots.reversed.toList();

    final drawVals = _pick(ordered, (s) => s.drawMs);
    final reactionVals = _pick(ordered, (s) => s.avgReactionMs);
    final splitVals = _pick(ordered, (s) => s.avgSplitMs);
    final transitionVals = _pick(ordered, (s) => s.avgTransitionMs);

    return ListView(
      padding: const EdgeInsets.all(AtriarchSpacing.lg),
      children: [
        const TacticalSection(code: 'TREND_01', trailing: 'PERFORMANCE TREND'),
        Text(
          'LAST ${snapshots.length} SESSIONS',
          style: AtriarchText.labelTiny(color: tokens.textTertiary),
        ),
        const SizedBox(height: AtriarchSpacing.lg),
        TrendMetricPanel(
          label: 'DRAW',
          unit: 'MS',
          values: drawVals,
          latestValue: drawVals.isNotEmpty ? drawVals.last : null,
          bestValue: drawVals.isNotEmpty
              ? drawVals.reduce((a, b) => a < b ? a : b)
              : null,
        ),
        const SizedBox(height: AtriarchSpacing.md),
        TrendMetricPanel(
          label: 'AVG REACTION',
          unit: 'MS',
          values: reactionVals,
          latestValue: reactionVals.isNotEmpty ? reactionVals.last : null,
          bestValue: reactionVals.isNotEmpty
              ? reactionVals.reduce((a, b) => a < b ? a : b)
              : null,
        ),
        const SizedBox(height: AtriarchSpacing.md),
        TrendMetricPanel(
          label: 'AVG SPLIT',
          unit: 'MS',
          values: splitVals,
          latestValue: splitVals.isNotEmpty ? splitVals.last : null,
          bestValue: splitVals.isNotEmpty
              ? splitVals.reduce((a, b) => a < b ? a : b)
              : null,
        ),
        const SizedBox(height: AtriarchSpacing.md),
        TrendMetricPanel(
          label: 'AVG TRANSITION',
          unit: 'MS',
          values: transitionVals,
          latestValue: transitionVals.isNotEmpty ? transitionVals.last : null,
          bestValue: transitionVals.isNotEmpty
              ? transitionVals.reduce((a, b) => a < b ? a : b)
              : null,
        ),
        const SizedBox(height: AtriarchSpacing.xxl),
      ],
    );
  }

  static List<int> _pick(
    List<MetricSnapshot> ordered,
    int? Function(MetricSnapshot) extractor,
  ) =>
      ordered.map(extractor).whereType<int>().toList();
}
