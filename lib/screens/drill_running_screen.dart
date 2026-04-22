import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/drill_timer.dart';
import '../widgets/tactical/tactical_hud_tile.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_status_chip.dart';
import 'results_screen.dart';

class DrillRunningScreen extends StatefulWidget {
  const DrillRunningScreen({super.key});

  @override
  State<DrillRunningScreen> createState() => _DrillRunningScreenState();
}

class _DrillRunningScreenState extends State<DrillRunningScreen>
    with TickerProviderStateMixin {
  late final AnimationController _breatheController;
  AppState? _boundState;

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    final state = context.read<AppState>();
    _boundState = state;
    state.addListener(_checkDrillComplete);
  }

  @override
  void dispose() {
    _breatheController.dispose();
    _boundState?.removeListener(_checkDrillComplete);
    super.dispose();
  }

  void _checkDrillComplete() {
    if (!mounted) return;
    final state = context.read<AppState>();
    if (state.phase == DrillPhase.finished) {
      // Detach before navigating — see note in ProgramBSetupScreen. The
      // Running screen is about to be disposed but the transition animates
      // for ~300ms; a late notifyListeners during that window would re-fire
      // pushReplacement and stack duplicate Results screens.
      state.removeListener(_checkDrillComplete);
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
        final statusColor =
            stopping ? tokens.statusArmed : tokens.statusLive;
        final statusLabel = stopping ? 'stopping' : 'live';
        return PopScope(
          canPop: false,
          child: TacticalScaffold(
            title: 'DRILL // LIVE',
            trailing: TacticalStatusChip(
              color: statusColor,
              label: statusLabel,
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AtriarchSpacing.lg),
                child: Column(
                  children: [
                    const SizedBox(height: AtriarchSpacing.xl),
                    _DrillActiveLabel(
                      color: tokens.statusArmed,
                      reduceMotion: reduceMotion,
                      breathe: _breatheController,
                    ),
                    const SizedBox(height: AtriarchSpacing.xl),
                    _HeroTimerWithBrackets(child: const DrillTimer()),
                    const SizedBox(height: AtriarchSpacing.xl),
                    Row(
                      children: const [
                        Expanded(
                          child: TacticalHudTile(
                            label: 'hits',
                            value: '—',
                          ),
                        ),
                        SizedBox(width: AtriarchSpacing.sm),
                        Expanded(
                          child: TacticalHudTile(
                            label: 'elapsed',
                            value: '—',
                          ),
                        ),
                        SizedBox(width: AtriarchSpacing.sm),
                        Expanded(
                          child: TacticalHudTile(
                            label: 'node',
                            value: '—',
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _StopButton(
                      onStop: _onStopConfirmed,
                      isStopping: stopping,
                    ),
                    const SizedBox(height: AtriarchSpacing.md),
                    Text(
                      stopping
                          ? 'ENDING DRILL…'
                          : 'PRESS AND HOLD TO ABORT',
                      style: AtriarchText.labelTiny(
                        color: tokens.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AtriarchSpacing.lg),
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

class _HeroTimerWithBrackets extends StatelessWidget {
  final Widget child;
  const _HeroTimerWithBrackets({required this.child});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return SizedBox(
      height: 140,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _CornerBracketPainter(color: tokens.statusHit),
            ),
          ),
          Center(child: child),
        ],
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  final Color color;
  _CornerBracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const armLen = 16.0;
    const inset = 4.0;

    // top-left
    canvas.drawLine(Offset(inset, inset), Offset(inset + armLen, inset), paint);
    canvas.drawLine(Offset(inset, inset), Offset(inset, inset + armLen), paint);
    // top-right
    canvas.drawLine(
      Offset(size.width - inset - armLen, inset),
      Offset(size.width - inset, inset),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - inset, inset),
      Offset(size.width - inset, inset + armLen),
      paint,
    );
    // bottom-left
    canvas.drawLine(
      Offset(inset, size.height - inset),
      Offset(inset + armLen, size.height - inset),
      paint,
    );
    canvas.drawLine(
      Offset(inset, size.height - inset - armLen),
      Offset(inset, size.height - inset),
      paint,
    );
    // bottom-right
    canvas.drawLine(
      Offset(size.width - inset - armLen, size.height - inset),
      Offset(size.width - inset, size.height - inset),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - inset, size.height - inset - armLen),
      Offset(size.width - inset, size.height - inset),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
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
                width: 180,
                height: 180,
                color: buttonColor,
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
                              fontWeight: FontWeight.w900,
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
