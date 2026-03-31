import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/session_event.dart';
import '../widgets/drill_timer.dart';
import 'results_screen.dart';

class DrillRunningScreen extends StatefulWidget {
  const DrillRunningScreen({super.key});

  @override
  State<DrillRunningScreen> createState() => _DrillRunningScreenState();
}

class _DrillRunningScreenState extends State<DrillRunningScreen> {
  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    state.addListener(_checkDrillComplete);
  }

  @override
  void dispose() {
    final state = context.read<AppState>();
    state.removeListener(_checkDrillComplete);
    super.dispose();
  }

  void _checkDrillComplete() {
    final state = context.read<AppState>();
    if (state.currentSession != null && !state.currentSession!.isRunning) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ResultsScreen()),
      );
    }
  }

  void _stopDrill() async {
    final state = context.read<AppState>();
    await state.stopDrill();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && state.currentSession?.isRunning == true) {
        state.currentSession!.addEvent(SessionEvent(type: EventType.drillFinished));
        state.notifyListeners();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('DRILL ACTIVE',
                  style: TextStyle(
                      color: Colors.green,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4)),
              const SizedBox(height: 40),
              const DrillTimer(),
              const SizedBox(height: 60),
              SizedBox(
                width: 200,
                height: 200,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: const CircleBorder(),
                  ),
                  onPressed: _stopDrill,
                  child: const Text('STOP',
                      style: TextStyle(
                          fontSize: 32,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
