import 'package:flutter/material.dart';
import '../../models/target_unit.dart';
import '../../theme/atriarch_theme.dart';

class TargetNodeChip extends StatelessWidget {
  final TargetUnit target;
  final VoidCallback onTap;

  const TargetNodeChip({
    super.key,
    required this.target,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final dotColor = !target.isOnline
        ? tokens.statusOffline
        : target.isNoShoot
            ? tokens.statusViolation
            : target.isUnreachable
                ? tokens.statusArmed
                : tokens.statusLive;

    return Material(
      color: tokens.bgCard,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            border: Border.all(
              color: tokens.border.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  target.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
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
