import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/session_record.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_scaffold.dart';

/// Recent drills — tactical list driven by [RangeSessionView].
///
/// Shows sessions that fall within the current range-session cutoff (last
/// activity, 8h inactivity rule). Replaces gate-2's SessionSummary-driven
/// version.
class RecentDrillsScreen extends StatefulWidget {
  const RecentDrillsScreen({super.key});

  @override
  State<RecentDrillsScreen> createState() => _RecentDrillsScreenState();
}

class _RecentDrillsScreenState extends State<RecentDrillsScreen> {
  Future<List<SessionRecord>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Wire the future after context is available; didChangeDependencies is
    // safe here because we only query once and the screen is single-shot.
    _future ??= _loadDrills();
  }

  Future<List<SessionRecord>> _loadDrills() async {
    final view = context.read<AppState>().rangeSessionView;
    if (view == null) return <SessionRecord>[];
    return view.listCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalScaffold(
      title: 'RECENT_DRILLS',
      body: FutureBuilder<List<SessionRecord>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final drills = snap.data ?? const <SessionRecord>[];
          if (drills.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AtriarchSpacing.lg),
                child: Text(
                  'NO DRILLS IN THE CURRENT RANGE SESSION.',
                  style: AtriarchText.labelTiny(color: tokens.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AtriarchSpacing.lg),
            itemCount: drills.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AtriarchSpacing.sm),
            itemBuilder: (_, i) => _DrillRow(record: drills[i]),
          );
        },
      ),
    );
  }
}

class _DrillRow extends StatelessWidget {
  final SessionRecord record;
  const _DrillRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final statusColor =
        record.finishedNormally ? tokens.statusLive : tokens.statusLate;
    final statusLabel =
        record.finishedNormally ? 'FIN' : 'INCOMPLETE';
    return TacticalCard(
      accent: statusColor,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PROGRAM_${record.programType} // '
                  '${record.id.substring(0, 8).toUpperCase()}',
                  style: AtriarchText.labelTiny(color: tokens.statusHit),
                ),
                const SizedBox(height: 4),
                Text(
                  _fmtTime(record.startedAt),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  '${record.iterationsCompleted} iteration'
                  '${record.iterationsCompleted == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textTertiary,
                      ),
                ),
              ],
            ),
          ),
          Text(
            statusLabel,
            style: AtriarchText.labelTiny(color: statusColor),
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
