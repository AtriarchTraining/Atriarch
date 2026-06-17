// lib/widgets/trend/trend_sparkline.dart
import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

enum _TrendDir { improving, declining, flat }

/// Custom-paint sparkline for a single metric series.
///
/// [values] is pre-filtered (nulls removed), oldest-to-newest.
/// Lower ms = faster = better, so a declining last-vs-mean is drawn green.
class TrendSparkline extends StatelessWidget {
  final List<int> values;
  final Color? improvingColor;
  final Color? decliningColor;
  final Color? flatColor;

  const TrendSparkline({
    super.key,
    required this.values,
    this.improvingColor,
    this.decliningColor,
    this.flatColor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return CustomPaint(
      painter: _SparklinePainter(
        values: values,
        improvingColor: improvingColor ?? tokens.statusLive,
        decliningColor: decliningColor ?? tokens.statusViolation,
        flatColor: flatColor ?? tokens.textTertiary,
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> values;
  final Color improvingColor;
  final Color decliningColor;
  final Color flatColor;

  const _SparklinePainter({
    required this.values,
    required this.improvingColor,
    required this.decliningColor,
    required this.flatColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final minVal = values.reduce((a, b) => a < b ? a : b).toDouble();
    final maxVal = values.reduce((a, b) => a > b ? a : b).toDouble();
    final range = maxVal - minVal;
    const vPad = 4.0;
    final drawH = size.height - vPad * 2;

    Offset pt(int i, int v) {
      final x = values.length == 1
          ? size.width / 2
          : i / (values.length - 1) * size.width;
      final y = range < 1
          ? size.height / 2
          : vPad + (1 - (v - minVal) / range) * drawH;
      return Offset(x, y);
    }

    final mean = values.fold<int>(0, (s, v) => s + v) / values.length;
    final last = values.last.toDouble();
    _TrendDir dir;
    if (values.length < 2) {
      dir = _TrendDir.flat;
    } else if ((mean - last).abs() < mean * 0.02) {
      dir = _TrendDir.flat;
    } else if (last < mean) {
      dir = _TrendDir.improving;
    } else {
      dir = _TrendDir.declining;
    }

    final lineColor = dir == _TrendDir.improving
        ? improvingColor
        : dir == _TrendDir.declining
            ? decliningColor
            : flatColor;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (values.length >= 2) {
      final path = Path()..moveTo(pt(0, values[0]).dx, pt(0, values[0]).dy);
      for (var i = 1; i < values.length; i++) {
        final p = pt(i, values[i]);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, linePaint);
    }

    final dotPaint = Paint()..style = PaintingStyle.fill;
    canvas.drawCircle(pt(0, values.first), 2.5,
        dotPaint..color = lineColor.withValues(alpha: 0.5));
    canvas.drawCircle(
        pt(values.length - 1, values.last), 3.5, dotPaint..color = lineColor);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values ||
      old.improvingColor != improvingColor ||
      old.decliningColor != decliningColor ||
      old.flatColor != flatColor;
}
