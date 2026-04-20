import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/drill_timer.dart';
import 'results_screen.dart';

// Addendum §7.1: STOP is press-and-hold, 800ms ring-fill. Single tap no-op.
// Addendum §3: after completion, enter STOPPING state until FIN/ arrives
// (or a 2s grace window elapses — Gate 1 fallback before STOP_ACK lands).
// Addendum §motion: DRILL ACTIVE breathe-pulses 2s opacity 0.75→1.0→0.75.

class DrillRunningScreen extends StatefulWidget {
  const DrillRunningScreen({super.key});

  @override
  State<DrillRunningScreen> createState() => _DrillRunningScreenState();
}

class _DrillRunningScreenState extends State<DrillRunningScreen>
    with TickerProviderStateMixin {
  late final AnimationController _breatheController;

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    final state = context.read<AppState>();
    state.addListener(_checkDrillComplete);
  }

  @override
  void dispose() {
    _breatheController.dispose();
    final state = context.read<AppState>();
    state.removeListener(_checkDrillComplete);
    super.dispose();
  }

  void _checkDrillComplete() {
    if (!mounted) return;
    final state = context.read<AppState>();
    if (state.phase == DrillPhase.finished) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ResultsScreen()),
      );
    }
  }

  Future<void> _onStopConfirmed() async {
    final state = context.read<AppState>();
    if (state.phase == DrillPhase.stopping ||
        state.phase == DrillPhase.finished) {
      return;
    }
    await state.stopDrill();
    // Gate 1 fallback: if STOP_ACK isn't landed on firmware yet, force the
    // nav after 2s. AppState.stopDrill itself has a 5s aggregate fallback;
    // this 2s belt-and-suspenders is the UI-layer guard we already had.
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      state.forceDrillFinished();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Consumer<AppState>(
      builder: (context, state, _) {
        final stopping = state.phase == DrillPhase.stopping;
        return PopScope(
          canPop: false,
          child: Scaffold(
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _DrillActiveLabel(
                      color: tokens.statusArmed,
                      reduceMotion: reduceMotion,
                      breathe: _breatheController,
                    ),
                    const SizedBox(height: AtriarchSpacing.xxxl),
                    const DrillTimer(),
                    const SizedBox(height: AtriarchSpacing.hero),
                    _StopButton(
                      onStop: _onStopConfirmed,
                      isStopping: stopping,
                    ),
                    const SizedBox(height: AtriarchSpacing.lg),
                    Text(
                      stopping ? 'Ending drill…' : 'Press and hold to stop',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: tokens.textTertiary,
                            letterSpacing: 0.8,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DrillActiveLabel extends StatelessWidget {
  final Color color;
  final bool reduceMotion;
  final AnimationController breathe;

  const _DrillActiveLabel({
    required this.color,
    required this.reduceMotion,
    required this.breathe,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.displaySmall?.copyWith(
          color: color,
          letterSpacing: 4,
          fontWeight: FontWeight.w700,
        );
    final label = Text('DRILL ACTIVE', style: style);

    if (reduceMotion) return label;

    return AnimatedBuilder(
      animation: breathe,
      builder: (_, __) {
        final t = breathe.value;
        final opacity = 0.75 + (t * 0.25);
        return Opacity(opacity: opacity, child: label);
      },
    );
  }
}

class _StopButton extends StatefulWidget {
  final Future<void> Function() onStop;
  final bool isStopping;

  const _StopButton({
    required this.onStop,
    required this.isStopping,
  });

  @override
  State<_StopButton> createState() => _StopButtonState();
}

class _StopButtonState extends State<_StopButton>
    with TickerProviderStateMixin {
  late final AnimationController _ring;

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _ring.addStatusListener(_onRingStatus);
  }

  @override
  void dispose() {
    _ring.removeStatusListener(_onRingStatus);
    _ring.dispose();
    super.dispose();
  }

  void _onRingStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !widget.isStopping) {
      widget.onStop();
    }
  }

  void _onDown() {
    if (widget.isStopping) return;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      widget.onStop();
      return;
    }
    _ring.forward();
  }

  void _onReleaseOrCancel() {
    if (widget.isStopping) return;
    if (_ring.value < 1.0) {
      _ring.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final buttonColor =
        widget.isStopping ? tokens.statusOffline : tokens.statusViolation;

    return Semantics(
      button: true,
      enabled: !widget.isStopping,
      label: 'Stop button. Press and hold to end the drill.',
      child: Listener(
        onPointerDown: (_) => _onDown(),
        onPointerUp: (_) => _onReleaseOrCancel(),
        onPointerCancel: (_) => _onReleaseOrCancel(),
        child: SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _ring,
                builder: (_, __) => CustomPaint(
                  size: const Size(220, 220),
                  painter: _StopRingPainter(
                    progress: _ring.value,
                    color: tokens.statusViolation,
                  ),
                ),
              ),
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: buttonColor,
                ),
                alignment: Alignment.center,
                child: widget.isStopping
                    ? _StoppingLabel(tokens: tokens)
                    : Text(
                        'STOP',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3,
                            ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoppingLabel extends StatelessWidget {
  final AtriarchTokens tokens;

  const _StoppingLabel({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 3,
          ),
        ),
        const SizedBox(height: AtriarchSpacing.md),
        Text(
          'STOPPING…',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
        ),
      ],
    );
  }
}

class _StopRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _StopRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 6;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_StopRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
