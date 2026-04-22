import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/session_event.dart';
import '../state/app_state.dart';
import '../util/results_view_model.dart';
import '../util/target_name_resolver.dart';
import '../util/widget_to_image.dart';
import '../widgets/drill_result_image.dart';
import '../widgets/drill_share_sheet.dart';
import '../theme/atriarch_theme.dart';
import 'home_screen.dart';

/// Results view. Renders either the live [DrillSession] held on [AppState]
/// or a hydrated [ResultsViewModel] when reached via Recent Drills in
/// read-only mode (#16).
class ResultsScreen extends StatelessWidget {
  /// Optional pre-built view model for historical renders. When null the
  /// widget falls back to [AppState.currentSession].
  final ResultsViewModel? viewModel;

  /// Read-only mode hides Run Again / New Drill actions. Reached via
  /// RecentDrillsScreen (#16).
  final bool readOnly;

  /// First-run onboarding wrap-up (Gate 2 #19). When true, renders a
  /// dismissible banner + a primary "Finish Onboarding" button that
  /// persists `app_settings.onboarding_complete = true` and pops back to
  /// Home, replacing the usual Home FAB.
  final bool onboardingMode;

  const ResultsScreen({
    super.key,
    this.viewModel,
    this.readOnly = false,
    this.onboardingMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final model = viewModel ?? _liveModel(context);
    if (model == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: const Center(child: Text('No session data.')),
      );
    }
    return _ResultsView(
      model: model,
      readOnly: readOnly,
      onboardingMode: onboardingMode,
    );
  }

  static ResultsViewModel? _liveModel(BuildContext context) {
    final state = context.read<AppState>();
    final session = state.currentSession;
    if (session == null) return null;
    return ResultsViewModel.fromLiveSession(
      session,
      presetName: session.presetName ?? 'Custom',
      resolver: state.targetNameResolver,
    );
  }
}

class _ResultsView extends StatefulWidget {
  final ResultsViewModel model;
  final bool readOnly;
  final bool onboardingMode;

  const _ResultsView({
    required this.model,
    required this.readOnly,
    required this.onboardingMode,
  });

  @override
  State<_ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends State<_ResultsView> {
  bool _onboardingBannerDismissed = false;

  ResultsViewModel get _model => widget.model;

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final events = _model.events;
    final resolver = _model.nameResolver;

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
        activations: activations.where((e) => e.targetId == id).length,
        completions: tCompletions.length,
        hits: hits.where((e) => e.targetId == id).length,
        noShoots: noShoots.where((e) => e.targetId == id).length,
        lateHits: lateHits.where((e) => e.targetId == id).length,
        avgCompletionMs: avgTime,
      );
    }

    final showOnboardingBanner =
        widget.onboardingMode && !_onboardingBannerDismissed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drill Results'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share drill',
            onPressed: () => _openShareSheet(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showOnboardingBanner)
              _OnboardingBanner(
                tokens: tokens,
                onDismiss: () =>
                    setState(() => _onboardingBannerDismissed = true),
              ),
            if (showOnboardingBanner)
              const SizedBox(height: AtriarchSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatCard('Duration', _formatDuration(_model.duration)),
                _StatCard('Activations', '${activations.length}'),
                _StatCard('Total Hits', '${hits.length}'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatCard('Completions', '${completions.length}',
                    color: Colors.green),
                _StatCard('No-Shoot', '${noShoots.length}',
                    color: noShoots.isEmpty ? Colors.green : Colors.red),
                _StatCard('Late Hits', '${lateHits.length}',
                    color: lateHits.isEmpty ? Colors.green : Colors.orange),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Per-Target Breakdown',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                columns: const [
                  DataColumn(label: Text('Target')),
                  DataColumn(label: Text('Hits')),
                  DataColumn(label: Text('Done')),
                  DataColumn(label: Text('Avg ms')),
                  DataColumn(label: Text('NS')),
                  DataColumn(label: Text('Late')),
                ],
                rows: perTarget.entries.map((entry) {
                  final s = entry.value;
                  return DataRow(cells: [
                    DataCell(Text(resolver.display(entry.key))),
                    DataCell(Text('${s.hits}')),
                    DataCell(Text('${s.completions}')),
                    DataCell(Text('${s.avgCompletionMs.toInt()}')),
                    DataCell(Text('${s.noShoots}',
                        style: TextStyle(
                            color: s.noShoots > 0 ? Colors.red : null))),
                    DataCell(Text('${s.lateHits}',
                        style: TextStyle(
                            color: s.lateHits > 0 ? Colors.orange : null))),
                  ]);
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Event Log',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...events
                .map((e) => _EventTile(event: e, resolver: resolver)),
            const SizedBox(height: 32),
          ],
        ),
      ),
      floatingActionButton: widget.onboardingMode
          ? null
          : FloatingActionButton(
              onPressed: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              ),
              child: const Icon(Icons.home),
            ),
      bottomNavigationBar: widget.onboardingMode
          ? _FinishOnboardingBar(
              onFinish: () => _finishOnboarding(context),
            )
          : null,
    );
  }

  Future<void> _finishOnboarding(BuildContext context) async {
    final state = context.read<AppState>();
    await state.setOnboardingComplete(true);
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  Future<void> _openShareSheet(BuildContext context) async {
    await DrillShareSheet.show(
      context,
      onShareImage: () => _shareImage(context),
      onExportJson: () => _exportJson(context),
    );
  }

  Future<void> _shareImage(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await captureWidgetToPng(
        DrillResultImage(model: _model),
        size: const Size(
          DrillResultImage.width,
          DrillResultImage.height,
        ),
      );
      final path = await _writeTempPng(bytes, _model.drillId);
      await Share.shareXFiles(
        [XFile(path, mimeType: 'image/png')],
        subject: 'Atriarch drill result',
        text: '${_model.presetName} · ${_formatDuration(_model.duration)}',
      );
    } catch (e) {
      debugPrint('shareImage failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to share image.')),
      );
    }
  }

  Future<String> _writeTempPng(Uint8List bytes, String drillId) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/atriarch_drill_$drillId.png');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _exportJson(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<AppState>();
    try {
      final path = await state.drillLogs.exportLogToFile(_model.drillId);
      await Share.shareXFiles(
        [XFile(path, mimeType: 'application/json')],
        subject: 'Atriarch drill log',
        text: '${_model.presetName} · ${_formatDuration(_model.duration)}',
      );
    } catch (e) {
      debugPrint('exportJson failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Drill log not available.')),
      );
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s}s';
  }
}

class _TargetStats {
  final int activations;
  final int completions;
  final int hits;
  final int noShoots;
  final int lateHits;
  final double avgCompletionMs;

  _TargetStats({
    required this.activations,
    required this.completions,
    required this.hits,
    required this.noShoots,
    required this.lateHits,
    required this.avgCompletionMs,
  });
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatCard(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final SessionEvent event;
  final TargetNameResolver resolver;

  const _EventTile({required this.event, required this.resolver});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String text;

    String name(int? id) => id == null ? '?' : resolver.display(id);

    switch (event.type) {
      case EventType.targetActivated:
        icon = Icons.play_arrow;
        color = Colors.green;
        text = '${name(event.targetId)} activated';
      case EventType.hitDetected:
        icon = Icons.gps_fixed;
        color = Colors.blue;
        text =
            '${name(event.targetId)} hit ${event.hitNumber}/${event.requiredHits}';
      case EventType.targetComplete:
        icon = Icons.check_circle;
        color = Colors.green;
        text =
            '${name(event.targetId)} complete (${event.totalTimeMs}ms)';
      case EventType.noShootViolation:
        icon = Icons.warning;
        color = Colors.red;
        text = 'NO-SHOOT ${name(event.targetId)}!';
      case EventType.lateHit:
        icon = Icons.timer_off;
        color = Colors.orange;
        text = 'Late hit on ${name(event.targetId)}';
      case EventType.drillFinished:
        icon = Icons.flag;
        color = Colors.grey;
        text = 'Drill finished';
      case EventType.error:
        icon = Icons.error;
        color = Colors.red;
        text = 'Error: ${event.errorDetail}';
    }

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(text, style: const TextStyle(fontSize: 13)),
      trailing: Text(
        '${event.timestamp.hour}:${event.timestamp.minute.toString().padLeft(2, '0')}:${event.timestamp.second.toString().padLeft(2, '0')}',
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
    );
  }
}

/// Dismissible banner that renders at the top of Results when the screen is
/// reached from the first-run wizard (Gate 2 #19).
class _OnboardingBanner extends StatelessWidget {
  final AtriarchTokens tokens;
  final VoidCallback onDismiss;

  const _OnboardingBanner({required this.tokens, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AtriarchSpacing.md),
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        border: Border.all(color: tokens.statusLive),
        borderRadius: BorderRadius.circular(AtriarchRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: tokens.statusLive),
          const SizedBox(width: AtriarchSpacing.md),
          Expanded(
            child: Text(
              "You're set up! Tap Finish to head home.",
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                  ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}

/// Primary action bar shown in place of the Home FAB when Results is reached
/// from the first-run wizard.
class _FinishOnboardingBar extends StatelessWidget {
  final VoidCallback onFinish;

  const _FinishOnboardingBar({required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: onFinish,
            child: const Text('Finish Onboarding'),
          ),
        ),
      ),
    );
  }
}
