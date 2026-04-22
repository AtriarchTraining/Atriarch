import 'package:flutter/material.dart';

import '../../theme/atriarch_theme.dart';

/// Subtle 20px tactical grid drawn behind child content.
class TacticalGridBackground extends StatelessWidget {
  final Widget child;
  final double cellSize;
  final Color? lineColor;

  const TacticalGridBackground({
    super.key,
    required this.child,
    this.cellSize = 20,
    this.lineColor,
  }) : assert(cellSize > 0, 'cellSize must be positive');

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return CustomPaint(
      painter: _GridPainter(
        cellSize: cellSize,
        color: lineColor ?? tokens.border.withValues(alpha: 0.1),
      ),
      child: child,
    );
  }
}

class _GridPainter extends CustomPainter {
  final double cellSize;
  final Color color;

  _GridPainter({required this.cellSize, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += cellSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += cellSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.cellSize != cellSize || oldDelegate.color != color;
}
