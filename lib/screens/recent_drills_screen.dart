import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/session_summary.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../util/drill_log_codec.dart';
import '../util/results_view_model.dart';
import 'results_screen.dart';

/// Session-scoped drill history (addendum §4.E, #16).
///
/// Lists the drills completed since the current session started,
/// most-recent-first. Tap → opens [ResultsScreen] in read-only mode,
/// hydrated from the drill log JSON held by [DrillLogRepository].
class RecentDrillsScreen extends StatelessWidget {
  const RecentDrillsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recent Drills')),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          final drills = state.sessions.currentSessionDrills;
          if (drills.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AtriarchSpacing.xl),
                child: Text(
                  'No drills completed yet this session.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          // Most-recent-first: the repository appends in chronological
          // order, so reverse the list here without mutating the source.
          final ordered = drills.reversed.toList(growable: false);
          return ListView.separated(
            itemCount: ordered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _RecentDrillRow(summary: ordered[i]),
          );
        },
      ),
    );
  }
}

class _RecentDrillRow extends StatelessWidget {
  final SessionSummary summary;

  const _RecentDrillRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final total = summary.completions; // expected count derives from log
    final subtitle =
        '${total} completions · ${summary.violations} violations · '
        '${_formatDuration(summary.duration)}';
    return InkWell(
      onTap: () => _openHistorical(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AtriarchSpacing.lg,
          vertical: AtriarchSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.presetName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(summary.startedAt),
                    style: TextStyle(
                      fontSize: 13,
                      color: tokens.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Future<void> _openHistorical(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    String? jsonString;
    try {
      jsonString = await state.drillLogs.readLog(summary.drillId);
    } catch (e) {
      debugPrint('recent drill readLog failed: $e');
    }
    if (jsonString == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Drill log unavailable.')),
      );
      return;
    }
    try {
      final decoded = DrillLogCodec.decode(jsonString);
      final model = ResultsViewModel.fromDecodedLog(decoded);
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => ResultsScreen(viewModel: model, readOnly: true),
        ),
      );
    } catch (e) {
      debugPrint('recent drill decode failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open drill log.')),
      );
    }
  }

  String _formatTime(DateTime dt) {
    final hour24 = dt.hour;
    final hour12 = hour24 == 0
        ? 12
        : (hour24 > 12 ? hour24 - 12 : hour24);
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $suffix';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}
