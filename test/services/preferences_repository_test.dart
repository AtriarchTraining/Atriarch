import 'package:atriarch/services/preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PreferencesRepository', () {
    test('default preset id round-trips', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = PreferencesRepository(prefs);
      expect(await repo.getDefaultPresetId(), isNull);
      await repo.setDefaultPresetId('tpl-1');
      expect(await repo.getDefaultPresetId(), 'tpl-1');
      await repo.setDefaultPresetId(null);
      expect(await repo.getDefaultPresetId(), isNull);
    });

    test('target names round-trip', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = PreferencesRepository(prefs);
      expect(await repo.getTargetNames(), isEmpty);
      await repo.setTargetName(1, 'Alpha');
      await repo.setTargetName(2, 'Bravo');
      expect(await repo.getTargetNames(), {1: 'Alpha', 2: 'Bravo'});
      await repo.setTargetName(1, null); // remove
      expect(await repo.getTargetNames(), {2: 'Bravo'});
    });

    test('removed target ids round-trip', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = PreferencesRepository(prefs);
      expect(await repo.getRemovedTargetIds(), isEmpty);
      await repo.setRemovedTargetIds({3, 7, 1});
      expect(await repo.getRemovedTargetIds(), {1, 3, 7});
    });

    test('onboarding complete flag', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = PreferencesRepository(prefs);
      expect(await repo.isOnboardingComplete(), isFalse);
      await repo.setOnboardingComplete(true);
      expect(await repo.isOnboardingComplete(), isTrue);
    });

    test('range activity timestamp', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = PreferencesRepository(prefs);
      expect(await repo.getLastRangeActivity(), isNull);
      final t = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      await repo.setLastRangeActivity(t);
      expect(await repo.getLastRangeActivity(), t);
    });
  });
}
