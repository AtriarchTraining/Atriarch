import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/drill_config.dart';
import '../models/target_group.dart';
import '../widgets/inc_dec.dart';
import '../widgets/target_chip.dart';
import 'drill_running_screen.dart';

class ProgramASetupScreen extends StatefulWidget {
  const ProgramASetupScreen({super.key});

  @override
  State<ProgramASetupScreen> createState() => _ProgramASetupScreenState();
}

class _ProgramASetupScreenState extends State<ProgramASetupScreen> {
  final startMinCtrl = TextEditingController(text: '1.00');
  final startMaxCtrl = TextEditingController(text: '3.00');
  final delayMinCtrl = TextEditingController(text: '0.50');
  final delayMaxCtrl = TextEditingController(text: '2.00');
  final hitsMinCtrl = TextEditingController(text: '1.00');
  final hitsMaxCtrl = TextEditingController(text: '3.00');
  final iterCtrl = TextEditingController(text: '5.00');

  List<TargetGroup> groups = List.generate(5, (i) => TargetGroup(id: i + 1));
  int? selectedGroupIndex;

  void _startDrill() {
    final state = context.read<AppState>();

    final activeGroups = groups.where((g) => g.targetIds.isNotEmpty).toList();
    if (activeGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assign at least one target to a group.')),
      );
      return;
    }

    final noShootIds = state.targets
        .where((t) => t.isOnline && t.isNoShoot)
        .map((t) => t.id)
        .toList();

    final config = DrillConfig(
      programType: ProgramType.programA,
      startMin: double.tryParse(startMinCtrl.text) ?? 1.0,
      startMax: double.tryParse(startMaxCtrl.text) ?? 3.0,
      delayMin: double.tryParse(delayMinCtrl.text) ?? 0.5,
      delayMax: double.tryParse(delayMaxCtrl.text) ?? 2.0,
      hitsMin: (double.tryParse(hitsMinCtrl.text) ?? 1).toInt(),
      hitsMax: (double.tryParse(hitsMaxCtrl.text) ?? 3).toInt(),
      groups: groups,
      noShootIds: noShootIds,
      iterations: (double.tryParse(iterCtrl.text) ?? 5).toInt(),
    );

    state.startDrill(config);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DrillRunningScreen()),
    );
  }

  void _assignTargetToGroup(int targetId) {
    if (selectedGroupIndex == null) return;
    setState(() {
      for (final g in groups) {
        g.targetIds.remove(targetId);
      }
      groups[selectedGroupIndex!].targetIds.add(targetId);
    });
  }

  void _removeTargetFromGroup(int groupIndex, int targetId) {
    setState(() {
      groups[groupIndex].targetIds.remove(targetId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Program A - Group Mode')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Start Delay (seconds)'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IncDec(startMinCtrl, 'Min', 0.25),
                IncDec(startMaxCtrl, 'Max', 0.25),
              ],
            ),
            const SizedBox(height: 24),
            _sectionLabel('Time Between Activations (seconds)'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IncDec(delayMinCtrl, 'Min', 0.25),
                IncDec(delayMaxCtrl, 'Max', 0.25),
              ],
            ),
            const SizedBox(height: 24),
            _sectionLabel('Required Hits'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IncDec(hitsMinCtrl, 'Min'),
                IncDec(hitsMaxCtrl, 'Max'),
              ],
            ),
            const SizedBox(height: 24),
            _sectionLabel('Iterations per Group'),
            Center(child: IncDec(iterCtrl, 'Count')),
            const SizedBox(height: 32),
            _sectionLabel('Group Assignment'),
            const Text('Select a group, then tap online targets to assign them.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            ...List.generate(5, (i) => _buildGroupSection(i)),
            const SizedBox(height: 16),
            _sectionLabel('Available Targets'),
            Consumer<AppState>(
              builder: (_, state, __) {
                final assigned = groups.expand((g) => g.targetIds).toSet();
                final unassigned = state.targets
                    .where((t) => t.isOnline && !assigned.contains(t.id))
                    .toList();
                if (unassigned.isEmpty) {
                  return const Text('All online targets assigned.',
                      style: TextStyle(color: Colors.grey));
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: unassigned
                      .map((t) => TargetChip(
                            target: t,
                            onTap: () => _assignTargetToGroup(t.id),
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: _startDrill,
                child: const Text('START DRILL',
                    style: TextStyle(fontSize: 20, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupSection(int index) {
    final group = groups[index];
    final isSelected = selectedGroupIndex == index;
    return Card(
      color: isSelected ? Colors.blue.shade50 : null,
      child: InkWell(
        onTap: () => setState(() => selectedGroupIndex = index),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Group ${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.blue : null,
                  )),
              const SizedBox(height: 8),
              group.targetIds.isEmpty
                  ? const Text('No targets assigned',
                      style: TextStyle(color: Colors.grey))
                  : Wrap(
                      spacing: 4,
                      children: group.targetIds
                          .map((id) => Chip(
                                label: Text('T$id'),
                                onDeleted: () =>
                                    _removeTargetFromGroup(index, id),
                                deleteIconColor: Colors.red,
                              ))
                          .toList(),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}
