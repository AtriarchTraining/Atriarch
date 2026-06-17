// test/widgets/trend_sparkline_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/widgets/trend/trend_sparkline.dart';
import 'package:atriarch/theme/atriarch_theme.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(body: child),
      );

  testWidgets('renders without error with empty series', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(width: 200, height: 48, child: TrendSparkline(values: [])),
    ));
    expect(find.byType(TrendSparkline), findsOneWidget);
  });

  testWidgets('renders without error with one value', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(width: 200, height: 48, child: TrendSparkline(values: [450])),
    ));
    expect(find.byType(TrendSparkline), findsOneWidget);
  });

  testWidgets('renders without error with multiple values', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
          width: 200,
          height: 48,
          child: TrendSparkline(values: [500, 460, 430, 480, 410])),
    ));
    expect(find.byType(TrendSparkline), findsOneWidget);
  });

  testWidgets('accepts color overrides', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox(
        width: 200,
        height: 48,
        child: TrendSparkline(
          values: [500, 400],
          improvingColor: Color(0xFF39D98A),
          decliningColor: Color(0xFFFF3B4D),
        ),
      ),
    ));
    expect(find.byType(TrendSparkline), findsOneWidget);
  });
}
