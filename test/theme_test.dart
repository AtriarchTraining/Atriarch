import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';

void main() {
  testWidgets('dark theme uses Space Grotesk and zero radius', (tester) async {
    final theme = buildAtriarchDarkTheme();

    expect(theme.brightness, Brightness.dark);
    expect(theme.extension<AtriarchTokens>(), isNotNull);
    expect(theme.extension<AtriarchTokens>()!.bgBase, const Color(0xFF0A0D12));

    final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
    expect(cardShape.borderRadius, BorderRadius.zero);

    final btnStyle = theme.elevatedButtonTheme.style!;
    final btnShape =
        btnStyle.shape!.resolve({})! as RoundedRectangleBorder;
    expect(btnShape.borderRadius, BorderRadius.zero);
  });

  test('AtriarchRadius constants are all zero except full', () {
    expect(AtriarchRadius.sm, 0);
    expect(AtriarchRadius.md, 0);
    expect(AtriarchRadius.lg, 0);
    expect(AtriarchRadius.full, 9999);
  });
}
