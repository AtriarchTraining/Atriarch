import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

class TacticalStepper extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final double step;
  final String unit;
  final double? min;
  final double? max;
  final bool compact;
  final bool integer;

  const TacticalStepper({
    super.key,
    required this.controller,
    required this.label,
    this.step = 1.0,
    this.unit = '',
    this.min,
    this.max,
    this.compact = false,
    this.integer = false,
  });

  @override
  State<TacticalStepper> createState() => _TacticalStepperState();
}

class _TacticalStepperState extends State<TacticalStepper> {
  void _bump(double delta) {
    final current = double.tryParse(widget.controller.text) ?? 0;
    double next = current + delta;
    if (widget.min != null && next < widget.min!) next = widget.min!;
    if (widget.max != null && next > widget.max!) next = widget.max!;
    final formatted = widget.integer
        ? next.toInt().toString()
        : next.toStringAsFixed(2);
    setState(() {
      widget.controller.text = formatted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final btnSize = widget.compact ? 36.0 : 48.0;
    final numberStyle = widget.compact
        ? Theme.of(context).textTheme.titleLarge!.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: -0.5,
            )
        : Theme.of(context).textTheme.displaySmall!.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _SquareButton(
              size: btnSize,
              icon: Icons.remove,
              onTap: () => _bump(-widget.step),
            ),
            Expanded(
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: widget.controller,
                    builder: (_, __) => Text(
                      widget.controller.text,
                      style: numberStyle,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.label.toUpperCase(),
                    style: AtriarchText.labelTiny(color: tokens.textTertiary),
                  ),
                ],
              ),
            ),
            _SquareButton(
              size: btnSize,
              icon: Icons.add,
              onTap: () => _bump(widget.step),
            ),
          ],
        ),
        if (!widget.compact && widget.unit.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            widget.unit.toUpperCase(),
            style: AtriarchText.labelTiny(color: tokens.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _SquareButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final VoidCallback onTap;

  const _SquareButton({
    required this.size,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Material(
      color: tokens.bgElevated,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border.all(
              color: tokens.border.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Icon(icon, color: tokens.textPrimary, size: 20),
        ),
      ),
    );
  }
}
