import 'package:atriarch/data/in_memory_repositories.dart';
import 'package:atriarch/data/preferences_repository.dart';
import 'package:atriarch/theme/theme_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBrightness implements BrightnessController {
  double currentValue;
  final List<double> setCalls = [];

  _FakeBrightness({this.currentValue = 0.4});

  @override
  Future<double> get current async => currentValue;

  @override
  Future<void> setBrightness(double value) async {
    setCalls.add(value);
    currentValue = value;
  }
}

Future<PreferencesRepository> _newRepo({String? storedPreference}) async {
  final repo = InMemoryPreferencesRepository();
  await repo.init();
  if (storedPreference != null) {
    await repo.setSetting<String>(
      ThemeController.preferenceSettingKey,
      storedPreference,
    );
  }
  return repo;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeController — auto-theme schedule', () {
    test('auto preference at 10:00 local → LIGHT', () async {
      final repo = await _newRepo(storedPreference: 'auto');
      final ctrl = ThemeController(
        preferences: repo,
        now: () => DateTime(2026, 4, 20, 10, 0),
      );
      await ctrl.init();
      expect(ctrl.preference, ThemePreference.auto);
      expect(ctrl.themeMode, ThemeMode.light);
      ctrl.dispose();
    });

    test('auto preference at 20:00 local → DARK', () async {
      final repo = await _newRepo(storedPreference: 'auto');
      final ctrl = ThemeController(
        preferences: repo,
        now: () => DateTime(2026, 4, 20, 20, 0),
      );
      await ctrl.init();
      expect(ctrl.preference, ThemePreference.auto);
      expect(ctrl.themeMode, ThemeMode.dark);
      ctrl.dispose();
    });

    test('auto preference crossing 18:00 flips LIGHT → DARK on next tick',
        () async {
      final repo = await _newRepo(storedPreference: 'auto');
      fakeAsync((async) {
        // Start at 17:59:30, just before the boundary.
        var now = DateTime(2026, 4, 20, 17, 59, 30);
        final ctrl = ThemeController(
          preferences: repo,
          now: () => now,
        );
        ctrl.init();
        async.flushMicrotasks();
        expect(ctrl.themeMode, ThemeMode.light);

        // Advance 61s → now 18:00:31, crossing into DARK territory. The
        // minute-ticker should fire and re-resolve.
        now = now.add(const Duration(seconds: 61));
        async.elapse(const Duration(seconds: 61));
        expect(ctrl.themeMode, ThemeMode.dark);

        ctrl.dispose();
        async.flushMicrotasks();
      });
    });

    test(
        'manual setPreference(light) forces LIGHT regardless of clock; '
        'setPreference(auto) re-evaluates clock',
        () async {
      final repo = await _newRepo();
      // Clock says 20:00 (→ DARK in auto).
      final ctrl = ThemeController(
        preferences: repo,
        now: () => DateTime(2026, 4, 20, 20, 0),
      );
      await ctrl.init();
      // Default preference = auto; should resolve to DARK.
      expect(ctrl.preference, ThemePreference.auto);
      expect(ctrl.themeMode, ThemeMode.dark);

      // Manual light overrides the clock.
      await ctrl.setPreference(ThemePreference.light);
      expect(ctrl.themeMode, ThemeMode.light);

      // Back to auto re-reads the clock → DARK again.
      await ctrl.setPreference(ThemePreference.auto);
      expect(ctrl.themeMode, ThemeMode.dark);
      ctrl.dispose();
    });
  });

  group('ThemeController — preference persistence', () {
    test('setPreference(light) persists and applies immediately', () async {
      final repo = await _newRepo();
      final ctrl = ThemeController(
        preferences: repo,
        now: () => DateTime(2026, 4, 20, 10, 0),
      );
      await ctrl.init();
      await ctrl.setPreference(ThemePreference.light);
      expect(ctrl.themeMode, ThemeMode.light);
      expect(ctrl.preference, ThemePreference.light);
      final stored =
          await repo.getSetting<String>(ThemeController.preferenceSettingKey);
      expect(stored, 'light');
      ctrl.dispose();
    });

    test('stored preference loads on init', () async {
      final repo = await _newRepo(storedPreference: 'dark');
      final ctrl = ThemeController(
        preferences: repo,
        now: () => DateTime(2026, 4, 20, 10, 0),
      );
      await ctrl.init();
      expect(ctrl.preference, ThemePreference.dark);
      expect(ctrl.themeMode, ThemeMode.dark);
      ctrl.dispose();
    });
  });

  group('ThemeController — brightness override', () {
    test(
        'drill context active + resolved theme is LIGHT → brightness set to 1.0',
        () async {
      final repo = await _newRepo(storedPreference: 'light');
      final brightness = _FakeBrightness(currentValue: 0.3);
      final ctrl = ThemeController(
        preferences: repo,
        brightnessOverride: brightness,
      );
      await ctrl.init();
      ctrl.setDrillContextActive(true);
      // Let the brightness future resolve.
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.themeMode, ThemeMode.light);
      expect(brightness.setCalls, contains(1.0));
      ctrl.dispose();
    });

    test('lifecycle paused restores captured brightness; resume re-applies',
        () async {
      final repo = await _newRepo(storedPreference: 'light');
      final brightness = _FakeBrightness(currentValue: 0.3);
      final ctrl = ThemeController(
        preferences: repo,
        brightnessOverride: brightness,
      );
      await ctrl.init();
      ctrl.setDrillContextActive(true);
      await Future<void>.delayed(Duration.zero);
      expect(brightness.setCalls, contains(1.0));
      brightness.setCalls.clear();

      ctrl.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);
      expect(brightness.setCalls, contains(0.3));
      brightness.setCalls.clear();

      ctrl.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(brightness.setCalls, contains(1.0));
      ctrl.dispose();
    });

    test('setDrillContextActive(false) restores captured brightness',
        () async {
      final repo = await _newRepo(storedPreference: 'light');
      final brightness = _FakeBrightness(currentValue: 0.5);
      final ctrl = ThemeController(
        preferences: repo,
        brightnessOverride: brightness,
      );
      await ctrl.init();
      ctrl.setDrillContextActive(true);
      await Future<void>.delayed(Duration.zero);
      expect(brightness.setCalls, contains(1.0));
      brightness.setCalls.clear();

      ctrl.setDrillContextActive(false);
      await Future<void>.delayed(Duration.zero);
      expect(brightness.setCalls, contains(0.5));
      ctrl.dispose();
    });

    test('no override when drill context inactive', () async {
      final repo = await _newRepo(storedPreference: 'light');
      final brightness = _FakeBrightness();
      final ctrl = ThemeController(
        preferences: repo,
        brightnessOverride: brightness,
      );
      await ctrl.init();
      // Never set drill context active.
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.themeMode, ThemeMode.light);
      expect(brightness.setCalls, isEmpty);
      ctrl.dispose();
    });

    test('entering DARK (via schedule tick) reverts brightness override',
        () async {
      final repo = await _newRepo(storedPreference: 'auto');
      fakeAsync((async) {
        var now = DateTime(2026, 4, 20, 17, 59, 30);
        final brightness = _FakeBrightness(currentValue: 0.4);
        final ctrl = ThemeController(
          preferences: repo,
          brightnessOverride: brightness,
          now: () => now,
        );
        ctrl.init();
        async.flushMicrotasks();
        ctrl.setDrillContextActive(true);
        async.flushMicrotasks();
        expect(ctrl.themeMode, ThemeMode.light);
        expect(brightness.setCalls, contains(1.0));
        brightness.setCalls.clear();

        // Cross 18:00 — schedule ticker flips to DARK, restoring brightness.
        now = now.add(const Duration(seconds: 61));
        async.elapse(const Duration(seconds: 61));
        async.flushMicrotasks();
        expect(ctrl.themeMode, ThemeMode.dark);
        expect(brightness.setCalls, contains(0.4));

        ctrl.dispose();
        async.flushMicrotasks();
      });
    });
  });
}
