import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/target_breakdown.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';

class TargetBreakdownScreen extends StatefulWidget {
  const TargetBreakdownScreen({super.key});

  @override
  State<TargetBreakdownScreen> createState() => _TargetBreakdownScreenState();
}

class _TargetBreakdownScreenState extends State<TargetBreakdownScreen> {
  Future<List<TargetBreakdown>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<TargetBreakdown>> _load() async {
    final repo = context.read<AppState>().metricsRepo;
    if (repo == null) return const [];
    return repo.aggregateByTarget();
  }

  @override
  Widget build(BuildContext context) {
    return TacticalScaffold(
      title: 'TARGET_BREAKDOWN',
      body: FutureBuilder<List<TargetBreakdown>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data ?? const [];
          if (data.isEmpty) {
            final tokens = context.atriarch;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AtriarchSpacing.lg),
                child: Text(
                  'NO TARGET DATA AVAILABLE.\nComplete at least one drill to see breakdown.',
                  style: AtriarchText.labelTiny(color: tokens.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _BreakdownBody(breakdowns: data);
        },
      ),
    );
  }
}

class _BreakdownBody extends StatelessWidget {
  final List<TargetBreakdown> breakdowns;
  const _BreakdownBody({required this.breakdowns});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AtriarchSpacing.lg),
      children: [
        const TacticalSection(
          code: 'TGT_01',
          trailing: 'ALL-TIME · SLOWEST FIRST',
        ),
        const SizedBox(height: AtriarchSpacing.sm),
        ...breakdowns.map(
          (b) => Padding(
            padding: const EdgeInsets.only(bottom: AtriarchSpacing.sm),
            child: _TargetRow(breakdown: b),
          ),
        ),
        const SizedBox(height: AtriarchSpacing.xxl),
      ],
    );
  }
}

class _TargetRow extends StatelessWidget {
  final TargetBreakdown breakdown;
  const _TargetRow({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final b = breakdown;

    final Color accent;
    if (b.hasViolations) {
      accent = tokens.statusViolation;
    } else if (b.lateHitCount > 0) {
      accent = tokens.statusLate;
    } else {
      accent = tokens.border;
    }

    final hitPct = (b.hitRate * 100).round();

    return TacticalCard(
      accent: accent,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              'NODE_T${b.targetId}',
              style: AtriarchText.labelTiny(color: tokens.statusHit),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _kv('RXN', '${b.avgReactionMs}MS', tokens),
                  _kv('HIT', '$hitPct%', tokens),
                  _kv('ENG', '${b.totalEngagements}', tokens,
                      color: tokens.textTertiary),
                  if (b.hasViolations)
                    _kv('NS', '${b.noShootCount}', tokens,
                        color: tokens.statusViolation),
                  if (b.lateHitCount > 0)
                    _kv('LATE', '${b.lateHitCount}', tokens,
                        color: tokens.statusLate),
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
