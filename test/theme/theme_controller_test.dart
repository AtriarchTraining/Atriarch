import 'dart:async';

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

  group('ThemeController — lux hysteresis', () {
    test('under 2s of lux>1000 does not switch to LIGHT', () async {
      final repo = await _newRepo();
      fakeAsync((async) {
        final lux = StreamController<int>.broadcast();
        final ctrl = ThemeController(
          preferences: repo,
          luxStreamOverride: lux.stream,
        );
        ctrl.init();
        async.flushMicrotasks();
        // Park in DARK first.
        lux.add(50);
        async.elapse(const Duration(seconds: 3));
        expect(ctrl.themeMode, ThemeMode.dark);
        // Push into LIGHT zone for <2s and confirm no flip.
        lux.add(5000);
        async.elapse(const Duration(milliseconds: 500));
        expect(ctrl.themeMode, ThemeMode.dark);
        ctrl.dispose();
        unawaited(lux.close());
        async.flushMicrotasks();
      });
    });

    test('≥2s of lux>1000 switches to LIGHT', () async {
      final repo = await _newRepo();
      fakeAsync((async) {
        final lux = StreamController<int>.broadcast();
        final ctrl = ThemeController(
          preferences: repo,
          luxStreamOverride: lux.stream,
        );
        ctrl.init();
        async.flushMicrotasks();
        lux.add(5000);
        async.elapse(const Duration(seconds: 3));
        expect(ctrl.themeMode, ThemeMode.light);
        ctrl.dispose();
        unawaited(lux.close());
        async.flushMicrotasks();
      });
    });

    test('≥2s of lux<200 switches to DARK', () async {
      final repo = await _newRepo();
      fakeAsync((async) {
        final lux = StreamController<int>.broadcast();
        final ctrl = ThemeController(
          preferences: repo,
          luxStreamOverride: lux.stream,
        );
        ctrl.init();
        async.flushMicrotasks();
        lux.add(5000);
        async.elapse(const Duration(seconds: 3));
        expect(ctrl.themeMode, ThemeMode.light);
        lux.add(50);
        async.elapse(const Duration(seconds: 3));
        expect(ctrl.themeMode, ThemeMode.dark);
        ctrl.dispose();
        unawaited(lux.close());
        async.flushMicrotasks();
      });
    });

    test('flipping between zones within 2s does not switch', () async {
      final repo = await _newRepo();
      fakeAsync((async) {
        final lux = StreamController<int>.broadcast();
        final ctrl = ThemeController(
          preferences: repo,
          luxStreamOverride: lux.stream,
        );
        ctrl.init();
        async.flushMicrotasks();
        final initial = ctrl.themeMode;
        lux.add(5000);
        async.elapse(const Duration(milliseconds: 800));
        lux.add(50);
        async.elapse(const Duration(milliseconds: 800));
        lux.add(5000);
        async.elapse(const Duration(milliseconds: 800));
        // Total > 2s but no zone held for a full 2s.
        expect(ctrl.themeMode, initial);
        ctrl.dispose();
        unawaited(lux.close());
        async.flushMicrotasks();
      });
    });
  });

  group('ThemeController — schedule fallback', () {
    test(
        'sensor error at init marks sensorUnavailable and uses schedule (night → DARK)',
        () async {
      final repo = await _newRepo();
      fakeAsync((async) {
        final lux = StreamController<int>.broadcast();
        final ctrl = ThemeController(
          preferences: repo,
          luxStreamOverride: lux.stream,
          now: () => DateTime(2026, 4, 20, 23, 0),
        );
        ctrl.init();
        async.flushMicrotasks();
        lux.addError(Exception('no sensor'));
        async.flushMicrotasks();
        expect(ctrl.sensorUnavailable, isTrue);
        expect(ctrl.themeMode, ThemeMode.dark);
        ctrl.dispose();
        unawaited(lux.close());
        async.flushMicrotasks();
      });
    });

    test('schedule fallback returns LIGHT during daytime hours', () async {
      final repo = await _newRepo();
      fakeAsync((async) {
        final lux = StreamController<int>.broadcast();
        final ctrl = ThemeController(
          preferences: repo,
          luxStreamOverride: lux.stream,
          now: () => DateTime(2026, 4, 20, 12, 0),
        );
        ctrl.init();
        async.flushMicrotasks();
        lux.addError(Exception('no sensor'));
        async.flushMicrotasks();
        expect(ctrl.sensorUnavailable, isTrue);
        expect(ctrl.themeMode, ThemeMode.light);
        ctrl.dispose();
        unawaited(lux.close());
        async.flushMicrotasks();
      });
    });
  });

  group('ThemeController — preference persistence', () {
    test('setPreference(light) persists and applies immediately', () async {
      final repo = await _newRepo();
      final ctrl = ThemeController(preferences: repo);
      await ctrl.init();
      await ctrl.setPreference(ThemePreference.light);
      expect(ctrl.themeMode, ThemeMode.light);
      expect(ctrl.preference, ThemePreference.light);
      final stored =
          await repo.getSetting<String>(ThemeController.preferenceSettingKey);
      expect(stored, 'light');
      ctrl.dispose();
    });

    test('setPreference(dark) ignores subsequent lux readings', () async {
      final repo = await _newRepo();
      fakeAsync((async) {
        final lux = StreamController<int>.broadcast();
        final ctrl = ThemeController(
          preferences: repo,
          luxStreamOverride: lux.stream,
        );
        ctrl.init();
        async.flushMicrotasks();
        ctrl.setPreference(ThemePreference.dark);
        async.flushMicrotasks();
        // Pump a bright lux value; auto is off, stream is unsubscribed.
        lux.add(5000);
        async.elapse(const Duration(seconds: 3));
        expect(ctrl.themeMode, ThemeMode.dark);
        ctrl.dispose();
        unawaited(lux.close());
        async.flushMicrotasks();
      });
    });

    test('setPreference(auto) resumes lux-driven behavior', () async {
      final repo = await _newRepo();
      fakeAsync((async) {
        final lux = StreamController<int>.broadcast();
        final ctrl = ThemeController(
          preferences: repo,
          luxStreamOverride: lux.stream,
        );
        ctrl.init();
        async.flushMicrotasks();
        ctrl.setPreference(ThemePreference.dark);
        async.flushMicrotasks();
        ctrl.setPreference(ThemePreference.auto);
        async.flushMicrotasks();
        lux.add(5000);
        async.elapse(const Duration(seconds: 3));
        expect(ctrl.themeMode, ThemeMode.light);
        ctrl.dispose();
        unawaited(lux.close());
        async.flushMicrotasks();
      });
    });

    test('stored preference loads on init', () async {
      final repo = await _newRepo(storedPreference: 'dark');
      final ctrl = ThemeController(preferences: repo);
      await ctrl.init();
      expect(ctrl.preference, ThemePreference.dark);
      expect(ctrl.themeMode, ThemeMode.dark);
      ctrl.dispose();
    });
  });

  group('ThemeController — brightness override', () {
    test(
        'drill context active + resolved theme becomes LIGHT → brightness set to 1.0',
        () async {
      final repo = await _newRepo();
      fakeAsync((async) {
        final lux = StreamController<int>.broadcast();
        final brightness = _FakeBrightness(currentValue: 0.3);
        final ctrl = ThemeController(
          preferences: repo,
          luxStreamOverride: lux.stream,
          brightnessOverride: brightness,
        );
        ctrl.init();
        async.flushMicrotasks();
        ctrl.setDrillContextActive(true);
        async.flushMicrotasks();
        lux.add(5000);
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(ctrl.themeMode, ThemeMode.light);
        expect(brightness.setCalls, contains(1.0));
        ctrl.dispose();
        unawaited(lux.close());
        async.flushMicrotasks();
      });
    });

    test('lifecycle paused restores captured brightness; resume re-applies',
        () async {
      final repo = await _newRepo(storedPreference: 'light');
      fakeAsync((async) {
        final brightness = _FakeBrightness(currentValue: 0.3);
        final ctrl = ThemeController(
          preferences: repo,
          brightnessOverride: brightness,
        );
        ctrl.init();
        async.flushMicrotasks();
        ctrl.setDrillContextActive(true);
        async.flushMicrotasks();
        expect(brightness.setCalls, contains(1.0));
        brightness.setCalls.clear();

        ctrl.didChangeAppLifecycleState(AppLifecycleState.paused);
        async.flushMicrotasks();
        expect(brightness.setCalls, contains(0.3));
        brightness.setCalls.clear();

        ctrl.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(brightness.setCalls, contains(1.0));
        ctrl.dispose();
        async.flushMicrotasks();
      });
    });

    test('setDrillContextActive(false) restores captured brightness', () async {
      final repo = await _newRepo(storedPreference: 'light');
      fakeAsync((async) {
        final brightness = _FakeBrightness(currentValue: 0.5);
        final ctrl = ThemeController(
          preferences: repo,
          brightnessOverride: brightness,
        );
        ctrl.init();
        async.flushMicrotasks();
        ctrl.setDrillContextActive(true);
        async.flushMicrotasks();
        expect(brightness.setCalls, contains(1.0));
        brightness.setCalls.clear();

        ctrl.setDrillContextActive(false);
        async.flushMicrotasks();
        expect(brightness.setCalls, contains(0.5));
        ctrl.dispose();
        async.flushMicrotasks();
      });
    });

    test('no override when drill context inactive', () async {
      final repo = await _newRepo();
      fakeAsync((async) {
        final lux = StreamController<int>.broadcast();
        final brightness = _FakeBrightness();
        final ctrl = ThemeController(
          preferences: repo,
          luxStreamOverride: lux.stream,
          brightnessOverride: brightness,
        );
        ctrl.init();
        async.flushMicrotasks();
        lux.add(5000);
        async.elapse(const Duration(seconds: 3));
        expect(ctrl.themeMode, ThemeMode.light);
        expect(brightness.setCalls, isEmpty);
        ctrl.dispose();
        unawaited(lux.close());
        async.flushMicrotasks();
      });
    });
  });
}
