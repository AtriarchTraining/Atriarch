// lib/widgets/trend/trend_metric_panel.dart
import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';
import '../../widgets/tactical/tactical_card.dart';
import 'trend_sparkline.dart';

class TrendMetricPanel extends StatelessWidget {
  final String label;
  final String unit;
  final List<int> values;
  final int? latestValue;
  final int? bestValue;

  const TrendMetricPanel({
    super.key,
    required this.label,
    required this.unit,
    required this.values,
    this.latestValue,
    this.bestValue,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final hasData = values.isNotEmpty;

    String trendLabel;
    Color trendColor;
    if (!hasData || values.length < 2) {
      trendLabel = '—';
      trendColor = tokens.textTertiary;
    } else {
      final mean = values.fold<int>(0, (s, v) => s + v) / values.length;
      final last = values.last.toDouble();
      if ((mean - last).abs() < mean * 0.02) {
        trendLabel = 'STABLE';
        trendColor = tokens.textTertiary;
      } else if (last < mean) {
        trendLabel = 'IMPROVING';
        trendColor = tokens.statusLive;
      } else {
        trendLabel = 'DECLINING';
        trendColor = tokens.statusViolation;
      }
    }

    return TacticalCard(
      padding: const EdgeInsets.all(AtriarchSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: AtriarchText.labelTiny(color: tokens.textTertiary)),
              Text(trendLabel,
                  style: AtriarchText.labelTiny(color: trendColor)),
            ],
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          SizedBox(height: 48, child: TrendSparkline(values: values)),
          const SizedBox(height: AtriarchSpacing.sm),
          Row(
            children: [
              _hudPair(context, 'LAST',
                  latestValue != null ? '$latestValue$unit' : '--',
                  tokens.textPrimary),
              const SizedBox(width: AtriarchSpacing.xl),
              _hudPair(context, 'BEST',
                  bestValue != null ? '$bestValue$unit' : '--',
                  tokens.statusLive),
              if (!hasData) ...[
                const SizedBox(width: AtriarchSpacing.xl),
                Text('NO DATA',
                    style:
                        AtriarchText.labelTiny(color: tokens.textTertiary)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _hudPair(
      BuildContext context, String key, String val, Color valColor) {
    final tokens = context.atriarch;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$key ',
            style: AtriarchText.labelTiny(color: tokens.textTertiary)),
        Text(
          val,
          style: TextStyle(
            color: valColor,
            fontSize: 13,
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
