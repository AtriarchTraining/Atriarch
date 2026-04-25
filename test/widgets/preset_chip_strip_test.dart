import 'package:atriarch/models/drill_config.dart';
import 'package:atriarch/models/drill_template.dart';
import 'package:atriarch/services/config_hasher.dart';
import 'package:atriarch/widgets/preset_chip_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/fake_drill_template_repository.dart';
import '../test_helpers/fake_preferences_repository.dart';

DrillTemplate _tpl(String id, String name,
    {ProgramType type = ProgramType.programA}) {
  final cfg = DrillConfig(programType: type);
  return DrillTemplate(
    id: id,
    shooterId: null,
    name: name,
    programType: type,
    config: cfg,
    configHash: ConfigHasher.hash(cfg),
    createdAt: DateTime(2026),
  );
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('PresetChipStrip', () {
    testWidgets('shows only SAVE chip when no templates', (tester) async {
      final repo = FakeDrillTemplateRepository();
      await tester.pumpWidget(_wrap(
        PresetChipStrip(
          drillTemplates: repo,
          preferences: FakePreferencesRepository(),
          onLoad: (_) {},
          onSave: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('+ SAVE'), findsOneWidget);
      expect(find.textContaining('ALPHA'), findsNothing);
    });

    testWidgets('renders a chip for each template', (tester) async {
      final repo = FakeDrillTemplateRepository();
      await repo.insert(_tpl('a', 'ALPHA'));
      await repo.insert(_tpl('b', 'BETA'));
      await tester.pumpWidget(_wrap(
        PresetChipStrip(
          drillTemplates: repo,
          preferences: FakePreferencesRepository(),
          onLoad: (_) {},
          onSave: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('ALPHA'), findsOneWidget);
      expect(find.text('BETA'), findsOneWidget);
      expect(find.text('+ SAVE'), findsOneWidget);
    });

    testWidgets('auto-selects chip matching last-used preset id', (tester) async {
      final repo = FakeDrillTemplateRepository();
      await repo.insert(_tpl('a', 'ALPHA'));
      await repo.insert(_tpl('b', 'BETA'));
      final prefs = FakePreferencesRepository();
      await prefs.setDefaultPresetId('b');
      DrillTemplate? loaded;
      await tester.pumpWidget(_wrap(
        PresetChipStrip(
          drillTemplates: repo,
          preferences: prefs,
          onLoad: (t) => loaded = t,
          onSave: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(loaded?.id, 'b');
    });

    testWidgets('tapping a chip calls onLoad with that template', (tester) async {
      final repo = FakeDrillTemplateRepository();
      await repo.insert(_tpl('a', 'ALPHA'));
      DrillTemplate? loaded;
      await tester.pumpWidget(_wrap(
        PresetChipStrip(
          drillTemplates: repo,
          preferences: FakePreferencesRepository(),
          onLoad: (t) => loaded = t,
          onSave: () {},
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALPHA'));
      await tester.pump();
      expect(loaded?.id, 'a');
    });

    testWidgets('shows LOADED label when last-used preset auto-selected',
        (tester) async {
      final repo = FakeDrillTemplateRepository();
      await repo.insert(_tpl('a', 'ALPHA'));
      final prefs = FakePreferencesRepository();
      await prefs.setDefaultPresetId('a');
      await tester.pumpWidget(_wrap(
        PresetChipStrip(
          drillTemplates: repo,
          preferences: prefs,
          onLoad: (_) {},
          onSave: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('LOADED'), findsOneWidget);
    });

    testWidgets('banner resets when a different chip is tapped manually',
        (tester) async {
      final repo = FakeDrillTemplateRepository();
      await repo.insert(_tpl('a', 'ALPHA'));
      await repo.insert(_tpl('b', 'BETA'));
      final prefs = FakePreferencesRepository();
      await prefs.setDefaultPresetId('a');
      await tester.pumpWidget(_wrap(
        PresetChipStrip(
          drillTemplates: repo,
          preferences: prefs,
          onLoad: (_) {},
          onSave: () {},
        ),
      ));
      await tester.pumpAndSettle();
      // LOADED banner should be visible after auto-select
      expect(find.textContaining('LOADED'), findsOneWidget);
      // Tap the other chip
      await tester.tap(find.text('BETA'));
      await tester.pump();
      // Banner should be gone after manual selection
      expect(find.textContaining('LOADED'), findsNothing);
    });

    testWidgets('onSelectionChanged fires with the auto-selected template',
        (tester) async {
      final repo = FakeDrillTemplateRepository();
      final expectedTemplate = _tpl('b', 'BETA');
      await repo.insert(_tpl('a', 'ALPHA'));
      await repo.insert(expectedTemplate);
      final prefs = FakePreferencesRepository();
      await prefs.setDefaultPresetId('b');
      DrillTemplate? captured;
      await tester.pumpWidget(_wrap(
        PresetChipStrip(
          drillTemplates: repo,
          preferences: prefs,
          onLoad: (_) {},
          onSave: () {},
          onSelectionChanged: (t) => captured = t,
        ),
      ));
      await tester.pumpAndSettle();
      expect(captured?.id, expectedTemplate.id);
    });
  });
}
