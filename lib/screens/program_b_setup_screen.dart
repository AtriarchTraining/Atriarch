import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/drill_config.dart';
import '../widgets/inc_dec.dart';
import 'drill_running_screen.dart';

class ProgramBSetupScreen extends StatefulWidget {
  const ProgramBSetupScreen({super.key});

  @override
  State<ProgramBSetupScreen> createState() => _ProgramBSetupScreenState();
}

class _ProgramBSetupScreenState extends State<ProgramBSetupScreen> {
  final startMinCtrl = TextEditingController(text: '1.00');
  final startMaxCtrl = TextEditingController(text: '3.00');
  final delayMinCtrl = TextEditingController(text: '0.50');
  final delayMaxCtrl = TextEditingController(text: '2.00');
  final hitsMinCtrl = TextEditingController(text: '1.00');
  final hitsMaxCtrl = TextEditingController(text: '3.00');
  final iterCtrl = TextEditingController(text: '5.00');

  void _startDrill() {
    final state = context.read<AppState>();
    final onlineTargets = state.targets.where((t) => t.isOnline).toList();

    if (onlineTargets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No targets online. Run Target Setup first.')),
      );
      return;
    }

    final config = DrillConfig(
      programType: ProgramType.programB,
      startMin: double.tryParse(startMinCtrl.text) ?? 1.0,
      startMax: double.tryParse(startMaxCtrl.text) ?? 3.0,
      delayMin: double.tryParse(delayMinCtrl.text) ?? 0.5,
      delayMax: double.tryParse(delayMaxCtrl.text) ?? 2.0,
      hitsMin: (double.tryParse(hitsMinCtrl.text) ?? 1).toInt(),
      hitsMax: (double.tryParse(hitsMaxCtrl.text) ?? 3).toInt(),
      targetIds: onlineTargets.map((t) => t.id).toList(),
      noShootIds: onlineTargets.where((t) => t.isNoShoot).map((t) => t.id).toList(),
      iterations: (double.tryParse(iterCtrl.text) ?? 5).toInt(),
    );

    state.startDrill(config);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DrillRunningScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Program B - Individual Mode')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
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
            _sectionLabel('Iterations per Target'),
            Center(child: IncDec(iterCtrl, 'Count')),
            const SizedBox(height: 16),
            Consumer<AppState>(
              builder: (_, state, __) {
                final online = state.targets.where((t) => t.isOnline).length;
                final noShoot = state.targets.where((t) => t.isOnline && t.isNoShoot).length;
                return Text('$online target(s) online, $noShoot no-shoot',
                    style: const TextStyle(color: Colors.grey));
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

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}
