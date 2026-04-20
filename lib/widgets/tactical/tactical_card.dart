import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

class TacticalCard extends StatelessWidget {
  final Widget child;
  final Color? accent;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? background;

  const TacticalCard({
    super.key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(AtriarchSpacing.md),
    this.onTap,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final bg = background ?? tokens.bgCard;
    final border = accent != null
        ? Border(left: BorderSide(color: accent!, width: 2))
        : null;

    if (onTap == null) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(color: bg, border: border),
        child: child,
      );
    }

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(border: border),
          child: child,
        ),
      ),
    );
  }
}
