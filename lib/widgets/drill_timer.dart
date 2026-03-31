import 'dart:async';
import 'package:flutter/material.dart';

class DrillTimer extends StatefulWidget {
  const DrillTimer({super.key});

  @override
  State<DrillTimer> createState() => _DrillTimerState();
}

class _DrillTimerState extends State<DrillTimer> {
  final _stopwatch = Stopwatch()..start();
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final tenths = (d.inMilliseconds.remainder(1000) ~/ 100).toString();
    return '$minutes:$seconds.$tenths';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _format(_stopwatch.elapsed),
      style: const TextStyle(
        fontSize: 72,
        fontWeight: FontWeight.w300,
        fontFamily: 'monospace',
      ),
    );
  }
}
