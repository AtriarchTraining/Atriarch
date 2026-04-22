import 'package:atriarch/data/in_memory_repositories.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gate 2 #19 — onboarding gate (addendum §7.10).
///
/// Covers:
///  - `onboardingComplete` defaults to false on first launch.
///  - `setOnboardingComplete(true)` persists via PreferencesRepository.
///  - Hydration on init picks up the persisted value.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onboardingComplete defaults to false on first launch', () async {
    final prefs = InMemoryPreferencesRepository();
    await prefs.init();
    final state = AppState.forTest(preferences: prefs);
    // Let the async hydrate microtask complete.
    await Future<void>.delayed(Duration.zero);
    expect(state.onboardingComplete, isFalse);
    state.dispose();
  });

  test('setOnboardingComplete(true) persists via PreferencesRepository',
      () async {
    final prefs = InMemoryPreferencesRepository();
    await prefs.init();
    final state = AppState.forTest(preferences: prefs);
    await state.setOnboardingComplete(true);
    expect(state.onboardingComplete, isTrue);
    expect(
      await prefs.getSetting<bool>('onboarding_complete'),
      isTrue,
    );
    state.dispose();
  });

  test('hydrate on init picks up the persisted value', () async {
    final prefs = InMemoryPreferencesRepository();
    await prefs.init();
    await prefs.setSetting<bool>('onboarding_complete', true);

    final state = AppState.forTest(preferences: prefs);
    // The hydrate microtask runs after construction. Flush it.
    await Future<void>.delayed(Duration.zero);
    expect(state.onboardingComplete, isTrue);
    state.dispose();
  });

  test('setOnboardingComplete(false) clears the flag', () async {
    final prefs = InMemoryPreferencesRepository();
    await prefs.init();
    await prefs.setSetting<bool>('onboarding_complete', true);

    final state = AppState.forTest(preferences: prefs);
    await Future<void>.delayed(Duration.zero);
    expect(state.onboardingComplete, isTrue);

    await state.setOnboardingComplete(false);
    expect(state.onboardingComplete, isFalse);
    expect(
      await prefs.getSetting<bool>('onboarding_complete'),
      isFalse,
    );
    state.dispose();
  });

  test(
      'setter running before hydrate wins — late hydrate does not clobber user change',
      () async {
    final prefs = InMemoryPreferencesRepository();
    await prefs.init();
    // Pre-persist `true`. A fresh AppState() would normally hydrate to true,
    // but if the user taps "Re-run onboarding" before hydration lands the
    // setter-first race must survive.
    await prefs.setSetting<bool>('onboarding_complete', true);

    final state = AppState.forTest(preferences: prefs);
    // Setter fires before the hydrate microtask runs.
    await state.setOnboardingComplete(false);

    // Flush the hydrate microtask.
    await Future<void>.delayed(Duration.zero);

    // User's `false` must win.
    expect(state.onboardingComplete, isFalse);
    state.dispose();
  });
}
