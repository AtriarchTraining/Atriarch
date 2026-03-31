import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/session_event.dart';
import 'home_screen.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final session = state.currentSession;

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: const Center(child: Text('No session data.')),
      );
    }

    final events = session.events;
    final activations = events.where((e) => e.type == EventType.targetActivated).toList();
    final completions = events.where((e) => e.type == EventType.targetComplete).toList();
    final noShoots = events.where((e) => e.type == EventType.noShootViolation).toList();
    final lateHits = events.where((e) => e.type == EventType.lateHit).toList();
    final hits = events.where((e) => e.type == EventType.hitDetected).toList();

    final targetIds = activations.map((e) => e.targetId).whereType<int>().toSet();
    final perTarget = <int, _TargetStats>{};
    for (final id in targetIds) {
      final tCompletions = completions.where((e) => e.targetId == id).toList();
      final avgTime = tCompletions.isNotEmpty
          ? tCompletions.map((e) => e.totalTimeMs ?? 0).reduce((a, b) => a + b) /
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

    return Scaffold(
      appBar: AppBar(title: const Text('Drill Results')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatCard('Duration', _formatDuration(session.elapsed)),
                _StatCard('Activations', '${activations.length}'),
                _StatCard('Total Hits', '${hits.length}'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatCard('Completions', '${completions.length}', color: Colors.green),
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
                    DataCell(Text('T${entry.key}')),
                    DataCell(Text('${s.hits}')),
                    DataCell(Text('${s.completions}')),
                    DataCell(Text('${s.avgCompletionMs.toInt()}')),
                    DataCell(Text('${s.noShoots}',
                        style: TextStyle(color: s.noShoots > 0 ? Colors.red : null))),
                    DataCell(Text('${s.lateHits}',
                        style: TextStyle(color: s.lateHits > 0 ? Colors.orange : null))),
                  ]);
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Event Log',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...events.map((e) => _EventTile(event: e)),
            const SizedBox(height: 32),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        ),
        child: const Icon(Icons.home),
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
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final SessionEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String text;

    switch (event.type) {
      case EventType.targetActivated:
        icon = Icons.play_arrow;
        color = Colors.green;
        text = 'Target ${event.targetId} activated';
      case EventType.hitDetected:
        icon = Icons.gps_fixed;
        color = Colors.blue;
        text = 'Target ${event.targetId} hit ${event.hitNumber}/${event.requiredHits}';
      case EventType.targetComplete:
        icon = Icons.check_circle;
        color = Colors.green;
        text = 'Target ${event.targetId} complete (${event.totalTimeMs}ms)';
      case EventType.noShootViolation:
        icon = Icons.warning;
        color = Colors.red;
        text = 'NO-SHOOT Target ${event.targetId}!';
      case EventType.lateHit:
        icon = Icons.timer_off;
        color = Colors.orange;
        text = 'Late hit on Target ${event.targetId}';
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
