import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/drill_share_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper: pump a host widget that opens the share sheet via a button tap
/// so modal context is correct.
Future<void> _pumpAndOpenSheet(
  WidgetTester tester, {
  required VoidCallback onShareImage,
  required VoidCallback onExportJson,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAtriarchLightTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => DrillShareSheet.show(
                context,
                onShareImage: onShareImage,
                onExportJson: onExportJson,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders both action rows + Cancel', (tester) async {
    await _pumpAndOpenSheet(
      tester,
      onShareImage: () {},
      onExportJson: () {},
    );

    expect(find.text('Share drill'), findsOneWidget);
    expect(find.text('Share result image'), findsOneWidget);
    expect(find.text('for student'), findsOneWidget);
    expect(find.text('Export drill log (JSON)'), findsOneWidget);
    expect(find.text('for Jeremy'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('tapping Share result image fires onShareImage', (tester) async {
    var imageCalls = 0;
    var jsonCalls = 0;
    await _pumpAndOpenSheet(
      tester,
      onShareImage: () => imageCalls++,
      onExportJson: () => jsonCalls++,
    );
    await tester.tap(find.text('Share result image'));
    await tester.pumpAndSettle();
    expect(imageCalls, equals(1));
    expect(jsonCalls, equals(0));
    // Sheet dismisses on tap.
    expect(find.text('Share drill'), findsNothing);
  });

  testWidgets('tapping Export drill log fires onExportJson', (tester) async {
    var imageCalls = 0;
    var jsonCalls = 0;
    await _pumpAndOpenSheet(
      tester,
      onShareImage: () => imageCalls++,
      onExportJson: () => jsonCalls++,
    );
    await tester.tap(find.text('Export drill log (JSON)'));
    await tester.pumpAndSettle();
    expect(imageCalls, equals(0));
    expect(jsonCalls, equals(1));
  });

  testWidgets('Cancel dismisses without firing either callback',
      (tester) async {
    var imageCalls = 0;
    var jsonCalls = 0;
    await _pumpAndOpenSheet(
      tester,
      onShareImage: () => imageCalls++,
      onExportJson: () => jsonCalls++,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(imageCalls, equals(0));
    expect(jsonCalls, equals(0));
    expect(find.text('Share drill'), findsNothing);
  });
}
