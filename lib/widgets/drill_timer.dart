import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/atriarch_theme.dart';

class DrillTimer extends StatefulWidget {
  const DrillTimer({super.key});

  @override
  State<DrillTimer> createState() => _DrillTimerState();
}

class _DrillTimerState extends State<DrillTimer> {
  final _stopwatch = Stopwatch()..start();
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
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
    final tokens = context.atriarch;
    return Text(
      _format(_stopwatch.elapsed),
      style: GoogleFonts.jetBrainsMono(
        fontSize: 88,
        fontWeight: FontWeight.w300,
        color: tokens.textPrimary,
        height: 1.0,
        letterSpacing: -1,
      ),
    );
  }
}
