import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

enum TacticalButtonVariant { primary, loading, destructive, disabled }

class TacticalPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final TacticalButtonVariant variant;

  const TacticalPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = TacticalButtonVariant.primary,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final (bg, fg) = switch (variant) {
      TacticalButtonVariant.primary => (tokens.statusHit, tokens.bgBase),
      TacticalButtonVariant.loading => (tokens.statusHit, tokens.bgBase),
      TacticalButtonVariant.destructive => (
          tokens.statusViolation,
          tokens.bgBase,
        ),
      TacticalButtonVariant.disabled => (
          tokens.statusOffline,
          tokens.bgBase.withValues(alpha: 0.6),
        ),
    };
    final enabled = variant == TacticalButtonVariant.primary ||
        variant == TacticalButtonVariant.destructive;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: bg,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (variant == TacticalButtonVariant.loading) ...[
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: fg,
                    ),
                  ),
                  const SizedBox(width: AtriarchSpacing.md),
                ] else if (icon != null) ...[
                  Icon(icon, color: fg, size: 20),
                  const SizedBox(width: AtriarchSpacing.sm),
                ],
                Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
