import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';
import 'tactical_card.dart';
import 'tactical_stepper.dart';

class TacticalMinMaxCard extends StatelessWidget {
  final String title;
  final String? rangeHint;
  final TextEditingController minController;
  final TextEditingController maxController;
  final double step;
  final String unit;
  final double? min;
  final double? max;
  final bool integer;
  final Color? accent;

  const TacticalMinMaxCard({
    super.key,
    required this.title,
    required this.minController,
    required this.maxController,
    this.rangeHint,
    this.step = 0.25,
    this.unit = '',
    this.min,
    this.max,
    this.integer = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalCard(
      accent: accent ?? tokens.statusHit,
      padding: const EdgeInsets.all(AtriarchSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title.toUpperCase(),
                style: AtriarchText.labelTiny(color: tokens.textPrimary),
              ),
              if (rangeHint != null)
                Text(
                  rangeHint!,
                  style: AtriarchText.labelTiny(
                    color: tokens.statusHit.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AtriarchSpacing.md),
          Row(
            children: [
              Expanded(
                child: TacticalStepper(
                  controller: minController,
                  label: 'min',
                  step: step,
                  unit: unit,
                  min: min,
                  max: max,
                  compact: true,
                  integer: integer,
                ),
              ),
              Container(
                width: 1,
                height: 56,
                color: tokens.border.withValues(alpha: 0.3),
                margin: const EdgeInsets.symmetric(
                  horizontal: AtriarchSpacing.sm,
                ),
              ),
              Expanded(
                child: TacticalStepper(
                  controller: maxController,
                  label: 'max',
                  step: step,
                  unit: unit,
                  min: min,
                  max: max,
                  compact: true,
                  integer: integer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
