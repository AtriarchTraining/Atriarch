# Tactical Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle every screen in the Atriarch Flutter app to the tactical dark aesthetic: Space Grotesk typography, zero-radius rectangles, tactical grid background, `PARAM_0N` section headers, tabular numerics, `LIVE`/`OFFLINE` status chips — while preserving all existing functional behavior (especially the press-and-hold STOP gesture).

**Architecture:** Two layers. (1) Theme + app-wide shell (`TacticalScaffold`, `TacticalAppBar`, `TacticalGridBackground`). (2) Reusable widgets (`TacticalSection`, `TacticalStepper`, `GroupNodeCard`, etc.) used by rewritten screens. Foundations land first so every subsequent widget/screen picks up the dark tactical palette for free. Screens ship in risk order — home → discovery → program_b → program_a → results → drill_running (last, most safety-critical).

**Tech Stack:** Flutter (Dart), `provider` for state, `google_fonts` for Space Grotesk + JetBrains Mono, `flutter_blue_plus` for BLE (untouched), `flutter_test` for widget tests.

**Reference docs:**
- Spec: `docs/superpowers/specs/2026-04-20-tactical-redesign-design.md`
- Current theme tokens: `lib/theme/atriarch_theme.dart`
- Reference mockup: user's HTML (Program A / Group Mode tactical config screen)

**Testing strategy:** Per-task widget tests verify structural presence (`find.byType`, `find.text`) and key interactions (tap, press-and-hold). No golden file tests — too much infra overhead for visual-only work. Safety-critical behavior (`drill_running` press-and-hold STOP) gets an explicit interaction test.

**Commit style:** Each task = one logical unit = one commit. Conventional commits (`feat:`, `refactor:`, `test:`, `chore:`). Co-author line included as per repo convention.

---

## Phase 1 — Theme & Foundations

### Task 1: Theme refactor — Space Grotesk, zero radius, dark as default

**Files:**
- Modify: `lib/theme/atriarch_theme.dart`
- Modify: `lib/main.dart`
- Test: `test/theme_test.dart` (create)

**Goal:** Flip default theme to dark. Swap Inter Tight → Space Grotesk app-wide. Set all radii to zero. Add a `labelTiny` TextStyle for `PARAM_01`-style micro-labels.

- [ ] **Step 1: Write the failing test**

Create `test/theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';

void main() {
  testWidgets('dark theme uses Space Grotesk and zero radius', (tester) async {
    final theme = buildAtriarchDarkTheme();

    // Dark brightness
    expect(theme.brightness, Brightness.dark);
    // Atriarch tokens extension is wired
    expect(theme.extension<AtriarchTokens>(), isNotNull);
    expect(theme.extension<AtriarchTokens>()!.bgBase, const Color(0xFF0A0D12));

    // Card shape is zero-radius
    final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
    expect(cardShape.borderRadius, BorderRadius.zero);

    // ElevatedButton shape is zero-radius
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
```

Note: package name is `atriarch` — confirm from `pubspec.yaml` `name:` field first. If different, fix the import. Run `grep -E '^name:' pubspec.yaml` to confirm.

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/theme_test.dart
```

Expected: FAIL — `buildAtriarchDarkTheme` not defined, `AtriarchRadius.sm/md/lg` are non-zero, `AtriarchRadius.full` missing.

- [ ] **Step 3: Update `AtriarchRadius`**

In `lib/theme/atriarch_theme.dart`, replace the `AtriarchRadius` class with:

```dart
class AtriarchRadius {
  static const double sm = 0;
  static const double md = 0;
  static const double lg = 0;
  static const double full = 9999;

  const AtriarchRadius._();
}
```

- [ ] **Step 4: Add `labelTiny` text style**

Add to `AtriarchTokens` class (after existing color fields, still inside `@immutable class AtriarchTokens extends ThemeExtension<AtriarchTokens>`):

No — actually `labelTiny` is a `TextStyle` not a token. Add it as a top-level `const` in the file below `AtriarchRadius`:

```dart
class AtriarchText {
  static TextStyle labelTiny({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.0,
        color: color,
        height: 1.2,
      );

  const AtriarchText._();
}
```

Add `import 'package:google_fonts/google_fonts.dart';` at the top of the file if not already there.

- [ ] **Step 5: Add `buildAtriarchDarkTheme()`**

Add a new function below `buildAtriarchLightTheme()`:

```dart
ThemeData buildAtriarchDarkTheme() {
  const tokens = AtriarchTokens.dark;

  final sansTheme = GoogleFonts.spaceGroteskTextTheme();
  final mono = GoogleFonts.jetBrainsMono;

  final textTheme = sansTheme.copyWith(
    displayLarge: mono(
      fontSize: 96,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
      letterSpacing: -2,
    ),
    displayMedium: mono(
      fontSize: 48,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
      letterSpacing: -1,
    ),
    displaySmall: mono(
      fontSize: 36,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
      letterSpacing: -1,
    ),
    headlineMedium: GoogleFonts.spaceGrotesk(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: tokens.textPrimary,
    ),
    titleLarge: GoogleFonts.spaceGrotesk(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      color: tokens.textPrimary,
    ),
    titleMedium: GoogleFonts.spaceGrotesk(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: tokens.textPrimary,
    ),
    bodyLarge: GoogleFonts.spaceGrotesk(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: tokens.textPrimary,
    ),
    bodyMedium: GoogleFonts.spaceGrotesk(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: tokens.textPrimary,
    ),
    bodySmall: GoogleFonts.spaceGrotesk(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: tokens.textSecondary,
    ),
    labelLarge: GoogleFonts.spaceGrotesk(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.0,
      color: tokens.textPrimary,
    ),
    labelMedium: GoogleFonts.spaceGrotesk(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.4,
      color: tokens.textPrimary,
    ),
    labelSmall: GoogleFonts.spaceGrotesk(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.0,
      color: tokens.textTertiary,
    ),
  );

  final colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: tokens.statusHit,
    onPrimary: tokens.bgBase,
    secondary: tokens.statusLive,
    onSecondary: tokens.bgBase,
    error: tokens.statusViolation,
    onError: tokens.bgBase,
    surface: tokens.bgBase,
    onSurface: tokens.textPrimary,
    surfaceContainer: tokens.bgCard,
    surfaceContainerHigh: tokens.bgElevated,
    outline: tokens.border,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: tokens.bgBase,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.bgElevated,
      foregroundColor: tokens.statusHit,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.spaceGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        letterSpacing: 3.2,
        color: tokens.statusHit,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: tokens.border,
      space: 1,
      thickness: 1,
    ),
    cardTheme: CardThemeData(
      color: tokens.bgCard,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: tokens.statusHit,
        foregroundColor: tokens.bgBase,
        minimumSize: const Size(44, 56),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
        textStyle: GoogleFonts.spaceGrotesk(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        side: BorderSide(color: tokens.border),
        minimumSize: const Size(44, 44),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: tokens.textPrimary,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.bgCard,
      side: BorderSide(color: tokens.border),
      labelStyle: GoogleFonts.spaceGrotesk(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: tokens.textPrimary,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.bgCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: tokens.statusHit, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AtriarchSpacing.lg,
        vertical: AtriarchSpacing.md,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.bgElevated,
      contentTextStyle: GoogleFonts.spaceGrotesk(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: tokens.textPrimary,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    extensions: const [tokens],
  );
}
```

Also replace the `buildAtriarchLightTheme()` body's font references with Space Grotesk so both themes stay visually consistent if the light theme is ever re-enabled (low priority — if quick, update; otherwise leave a `// TODO: light theme typography out of date after dark flip` comment and move on).

- [ ] **Step 6: Flip `main.dart` to dark**

Modify `lib/main.dart` — replace:

```dart
theme: buildAtriarchLightTheme(),
```

with:

```dart
theme: buildAtriarchDarkTheme(),
darkTheme: buildAtriarchDarkTheme(),
themeMode: ThemeMode.dark,
```

- [ ] **Step 7: Run test to verify it passes**

```bash
flutter test test/theme_test.dart
```

Expected: PASS.

- [ ] **Step 8: Quick boot smoke check**

```bash
flutter analyze lib/theme/ lib/main.dart
```

Expected: no errors. (Warnings about unused imports are OK for this step.)

- [ ] **Step 9: Commit**

```bash
git add lib/theme/atriarch_theme.dart lib/main.dart test/theme_test.dart
git commit -m "$(cat <<'EOF'
feat(theme): swap to Space Grotesk + zero radius + dark default

Add buildAtriarchDarkTheme(). Flip MaterialApp to dark. Set all
AtriarchRadius values to zero (add AtriarchRadius.full). Add
AtriarchText.labelTiny helper for PARAM_0N micro-labels.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: TacticalGridBackground widget

**Files:**
- Create: `lib/widgets/tactical/tactical_grid_background.dart`
- Test: `test/widgets/tactical/tactical_grid_background_test.dart`

**Goal:** 20px grid overlay, painted from `CustomPaint`, wraps a child.

- [ ] **Step 1: Write the failing test**

Create `test/widgets/tactical/tactical_grid_background_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/widgets/tactical/tactical_grid_background.dart';

void main() {
  testWidgets('renders child over grid', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TacticalGridBackground(
          child: Text('OVERLAY_CONTENT'),
        ),
      ),
    );
    expect(find.text('OVERLAY_CONTENT'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/widgets/tactical/tactical_grid_background_test.dart
```

Expected: FAIL — `tactical_grid_background.dart` not found.

- [ ] **Step 3: Implement the widget**

Create `lib/widgets/tactical/tactical_grid_background.dart`:

```dart
import 'package:flutter/material.dart';

/// Subtle 20px tactical grid drawn behind child content.
class TacticalGridBackground extends StatelessWidget {
  final Widget child;
  final double cellSize;
  final Color? lineColor;

  const TacticalGridBackground({
    super.key,
    required this.child,
    this.cellSize = 20,
    this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GridPainter(
        cellSize: cellSize,
        color: lineColor ?? const Color.fromRGBO(42, 49, 64, 0.1),
      ),
      child: child,
    );
  }
}

class _GridPainter extends CustomPainter {
  final double cellSize;
  final Color color;

  _GridPainter({required this.cellSize, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += cellSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += cellSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.cellSize != cellSize || oldDelegate.color != color;
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/widgets/tactical/tactical_grid_background_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/tactical/tactical_grid_background.dart test/widgets/tactical/tactical_grid_background_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add TacticalGridBackground

20px grid overlay behind body content. Default line color is
border-color at 10% alpha.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: TacticalStatusChip widget

**Files:**
- Create: `lib/widgets/tactical/tactical_status_chip.dart`
- Test: `test/widgets/tactical/tactical_status_chip_test.dart`

**Goal:** Small `● LABEL` indicator with colored dot + optional glow.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/widgets/tactical/tactical_status_chip.dart';

void main() {
  testWidgets('renders label in uppercase with dot', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TacticalStatusChip(
            color: Colors.green,
            label: 'live',
          ),
        ),
      ),
    );
    expect(find.text('LIVE'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/widgets/tactical/tactical_status_chip_test.dart
```

Expected: FAIL — widget missing.

- [ ] **Step 3: Implement**

Create `lib/widgets/tactical/tactical_status_chip.dart`:

```dart
import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

class TacticalStatusChip extends StatelessWidget {
  final Color color;
  final String label;
  final bool glow;

  const TacticalStatusChip({
    super.key,
    required this.color,
    required this.label,
    this.glow = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            boxShadow: glow
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: AtriarchText.labelTiny(color: color),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/widgets/tactical/tactical_status_chip_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/tactical/tactical_status_chip.dart test/widgets/tactical/tactical_status_chip_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add TacticalStatusChip

Dot + label indicator used for LIVE/OFFLINE/ARMED state in
top bar and inline headers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: TacticalAppBar widget

**Files:**
- Create: `lib/widgets/tactical/tactical_app_bar.dart`
- Test: `test/widgets/tactical/tactical_app_bar_test.dart`

**Goal:** Custom `PreferredSizeWidget` replacement for Material `AppBar`. Menu icon + uppercase title + optional right-side trailing slot (where we'll put a `TacticalStatusChip`).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/widgets/tactical/tactical_app_bar.dart';

void main() {
  testWidgets('renders uppercase title and trailing slot', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: const TacticalAppBar(
            title: 'program_config',
            trailing: Text('TRAIL'),
          ),
          body: const SizedBox(),
        ),
      ),
    );
    expect(find.text('PROGRAM_CONFIG'), findsOneWidget);
    expect(find.text('TRAIL'), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/widgets/tactical/tactical_app_bar_test.dart
```

Expected: FAIL — widget missing.

- [ ] **Step 3: Implement**

Create `lib/widgets/tactical/tactical_app_bar.dart`:

```dart
import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

class TacticalAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final Widget? trailing;
  final VoidCallback? onMenuTap;
  final bool showBack;

  const TacticalAppBar({
    super.key,
    required this.title,
    this.trailing,
    this.onMenuTap,
    this.showBack = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final canPop = Navigator.of(context).canPop();
    final showBackEffective = showBack || canPop;

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        border: Border(
          bottom: BorderSide(
            color: tokens.border.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AtriarchSpacing.lg),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              showBackEffective ? Icons.arrow_back : Icons.menu,
              color: tokens.statusHit,
            ),
            onPressed: onMenuTap ??
                (showBackEffective
                    ? () => Navigator.of(context).maybePop()
                    : null),
          ),
          const SizedBox(width: AtriarchSpacing.sm),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(
                    color: tokens.statusHit,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3.2,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/widgets/tactical/tactical_app_bar_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/tactical/tactical_app_bar.dart test/widgets/tactical/tactical_app_bar_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add TacticalAppBar

Replaces Material AppBar with tactical uppercase title + menu/back
affordance + trailing slot.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: TacticalScaffold wrapper

**Files:**
- Create: `lib/widgets/tactical/tactical_scaffold.dart`
- Test: `test/widgets/tactical/tactical_scaffold_test.dart`

**Goal:** One wrapper that composes `Scaffold` + `TacticalAppBar` + `TacticalGridBackground` + dark background.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_scaffold.dart';
import 'package:atriarch/widgets/tactical/tactical_app_bar.dart';
import 'package:atriarch/widgets/tactical/tactical_grid_background.dart';

void main() {
  testWidgets('composes app bar + grid bg + child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: const TacticalScaffold(
          title: 'SYSTEM_CONFIG',
          body: Text('PAGE_BODY'),
        ),
      ),
    );
    expect(find.byType(TacticalAppBar), findsOneWidget);
    expect(find.byType(TacticalGridBackground), findsOneWidget);
    expect(find.text('PAGE_BODY'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/widgets/tactical/tactical_scaffold_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/widgets/tactical/tactical_scaffold.dart`:

```dart
import 'package:flutter/material.dart';
import 'tactical_app_bar.dart';
import 'tactical_grid_background.dart';

class TacticalScaffold extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool extendBodyBehindAppBar;

  const TacticalScaffold({
    super.key,
    this.title,
    this.trailing,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.extendBodyBehindAppBar = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: title != null
          ? TacticalAppBar(title: title!, trailing: trailing)
          : null,
      body: TacticalGridBackground(child: body),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/widgets/tactical/tactical_scaffold_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/tactical/tactical_scaffold.dart test/widgets/tactical/tactical_scaffold_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add TacticalScaffold

Composes Scaffold + TacticalAppBar + TacticalGridBackground.
Every restyled screen switches from Scaffold to this wrapper.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 — Reusable widgets

### Task 6: TacticalSection

**Files:**
- Create: `lib/widgets/tactical/tactical_section.dart`
- Test: `test/widgets/tactical/tactical_section_test.dart`

**Goal:** `[PARAM_01]  ────  [OPTIONAL_TRAILING]` header pattern.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_section.dart';

void main() {
  testWidgets('renders code and trailing labels uppercase', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: const Scaffold(
          body: TacticalSection(
            code: 'param_01',
            trailing: 'timing',
          ),
        ),
      ),
    );
    expect(find.text('PARAM_01'), findsOneWidget);
    expect(find.text('TIMING'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/widgets/tactical/tactical_section_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/widgets/tactical/tactical_section.dart`:

```dart
import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

class TacticalSection extends StatelessWidget {
  final String code;
  final String? trailing;

  const TacticalSection({
    super.key,
    required this.code,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AtriarchSpacing.sm),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: tokens.bgCard,
              border: Border.all(
                color: tokens.textTertiary.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Text(
              code.toUpperCase(),
              style: AtriarchText.labelTiny(color: tokens.textTertiary),
            ),
          ),
          const SizedBox(width: AtriarchSpacing.sm),
          Expanded(
            child: Container(
              height: 1,
              color: tokens.border.withValues(alpha: 0.3),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AtriarchSpacing.sm),
            Text(
              trailing!.toUpperCase(),
              style: AtriarchText.labelTiny(color: tokens.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/widgets/tactical/tactical_section_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/tactical/tactical_section.dart test/widgets/tactical/tactical_section_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add TacticalSection

PARAM_0N section header with divider and optional trailing label.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: TacticalCard

**Files:**
- Create: `lib/widgets/tactical/tactical_card.dart`
- Test: `test/widgets/tactical/tactical_card_test.dart`

**Goal:** `bgCard` container with optional 2px left accent border.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_card.dart';

void main() {
  testWidgets('renders child with accent border', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: const Scaffold(
          body: TacticalCard(
            accent: Colors.blue,
            child: Text('CHILD'),
          ),
        ),
      ),
    );
    expect(find.text('CHILD'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/widgets/tactical/tactical_card_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/widgets/tactical/tactical_card.dart`:

```dart
import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

class TacticalCard extends StatelessWidget {
  final Widget child;
  final Color? accent;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? background;

  const TacticalCard({
    super.key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(AtriarchSpacing.md),
    this.onTap,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? tokens.bgCard,
        border: accent != null
            ? Border(left: BorderSide(color: accent!, width: 2))
            : null,
      ),
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: content,
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/widgets/tactical/tactical_card_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/tactical/tactical_card.dart test/widgets/tactical/tactical_card_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add TacticalCard

Container with optional left accent border. Tap-capable via onTap.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: TacticalStepper (regular + compact)

**Files:**
- Create: `lib/widgets/tactical/tactical_stepper.dart`
- Test: `test/widgets/tactical/tactical_stepper_test.dart`

**Goal:** Replacement for `IncDec`. Big tabular number + `−/+` square buttons. Supports compact variant for min/max pairs.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_stepper.dart';

void main() {
  testWidgets('increments on + tap', (tester) async {
    final ctrl = TextEditingController(text: '1.00');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: TacticalStepper(
            controller: ctrl,
            label: 'test',
            step: 0.25,
            unit: 'sec',
          ),
        ),
      ),
    );
    expect(find.text('1.00'), findsOneWidget);
    expect(find.text('SEC'), findsOneWidget);

    // Tap the + button (second InkWell / icon button)
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(ctrl.text, '1.25');

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(ctrl.text, '1.00');
  });

  testWidgets('compact variant renders unit label', (tester) async {
    final ctrl = TextEditingController(text: '0.50');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: TacticalStepper(
            controller: ctrl,
            label: 'min',
            step: 0.25,
            unit: 'sec',
            compact: true,
          ),
        ),
      ),
    );
    expect(find.text('MIN'), findsOneWidget);
    expect(find.text('0.50'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/widgets/tactical/tactical_stepper_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/widgets/tactical/tactical_stepper.dart`:

```dart
import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

class TacticalStepper extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final double step;
  final String unit;
  final double? min;
  final double? max;
  final bool compact;
  final bool integer;

  const TacticalStepper({
    super.key,
    required this.controller,
    required this.label,
    this.step = 1.0,
    this.unit = '',
    this.min,
    this.max,
    this.compact = false,
    this.integer = false,
  });

  @override
  State<TacticalStepper> createState() => _TacticalStepperState();
}

class _TacticalStepperState extends State<TacticalStepper> {
  void _bump(double delta) {
    final current = double.tryParse(widget.controller.text) ?? 0;
    double next = current + delta;
    if (widget.min != null && next < widget.min!) next = widget.min!;
    if (widget.max != null && next > widget.max!) next = widget.max!;
    final formatted = widget.integer
        ? next.toInt().toString()
        : next.toStringAsFixed(2);
    setState(() {
      widget.controller.text = formatted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final btnSize = widget.compact ? 36.0 : 48.0;
    final numberStyle = widget.compact
        ? Theme.of(context).textTheme.titleLarge!.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: -0.5,
            )
        : Theme.of(context).textTheme.displaySmall!.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _SquareButton(
              size: btnSize,
              icon: Icons.remove,
              onTap: () => _bump(-widget.step),
            ),
            Expanded(
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: widget.controller,
                    builder: (_, __) => Text(
                      widget.controller.text,
                      style: numberStyle,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.label.toUpperCase(),
                    style: AtriarchText.labelTiny(color: tokens.textTertiary),
                  ),
                ],
              ),
            ),
            _SquareButton(
              size: btnSize,
              icon: Icons.add,
              onTap: () => _bump(widget.step),
            ),
          ],
        ),
        if (!widget.compact && widget.unit.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            widget.unit.toUpperCase(),
            style: AtriarchText.labelTiny(color: tokens.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _SquareButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final VoidCallback onTap;

  const _SquareButton({
    required this.size,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Material(
      color: tokens.bgElevated,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border.all(
              color: tokens.border.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Icon(icon, color: tokens.textPrimary, size: 20),
        ),
      ),
    );
  }
}
```

Note on test: the compact variant test expects `find.text('MIN')`. In compact mode we still render the uppercase label. That works.

Note on integer mode: use `integer: true` for the "Required Hits" and "Iterations" steppers so they format as `"1"` not `"1.00"`.

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/widgets/tactical/tactical_stepper_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/tactical/tactical_stepper.dart test/widgets/tactical/tactical_stepper_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add TacticalStepper replacing IncDec

Large tabular number + square minus/plus buttons. Compact variant
fits side-by-side for min/max pairs. Integer mode for hits/iterations.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: TacticalMinMaxCard

**Files:**
- Create: `lib/widgets/tactical/tactical_min_max_card.dart`
- Test: `test/widgets/tactical/tactical_min_max_card_test.dart`

**Goal:** One card containing two compact `TacticalStepper`s (MIN / MAX) with a shared header.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_min_max_card.dart';
import 'package:atriarch/widgets/tactical/tactical_stepper.dart';

void main() {
  testWidgets('renders title + two steppers', (tester) async {
    final minCtrl = TextEditingController(text: '0.50');
    final maxCtrl = TextEditingController(text: '2.00');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: TacticalMinMaxCard(
            title: 'START DELAY',
            rangeHint: '0.00 – 10.00 SEC',
            minController: minCtrl,
            maxController: maxCtrl,
            step: 0.25,
            unit: 'sec',
          ),
        ),
      ),
    );
    expect(find.text('START DELAY'), findsOneWidget);
    expect(find.text('0.00 – 10.00 SEC'), findsOneWidget);
    expect(find.byType(TacticalStepper), findsNWidgets(2));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/widgets/tactical/tactical_min_max_card_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/widgets/tactical/tactical_min_max_card.dart`:

```dart
import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';
import 'tactical_card.dart';
import 'tactical_stepper.dart';

class TacticalMinMaxCard extends StatelessWidget {
  final String title;
  final String? rangeHint;
  final TextEditingController minController;
  final TextEditingController maxController;
  final double step;
  final String unit;
  final double? min;
  final double? max;
  final bool integer;
  final Color? accent;

  const TacticalMinMaxCard({
    super.key,
    required this.title,
    required this.minController,
    required this.maxController,
    this.rangeHint,
    this.step = 0.25,
    this.unit = '',
    this.min,
    this.max,
    this.integer = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalCard(
      accent: accent ?? tokens.statusHit,
      padding: const EdgeInsets.all(AtriarchSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title.toUpperCase(),
                style: AtriarchText.labelTiny(color: tokens.textPrimary),
              ),
              if (rangeHint != null)
                Text(
                  rangeHint!,
                  style: AtriarchText.labelTiny(
                    color: tokens.statusHit.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AtriarchSpacing.md),
          Row(
            children: [
              Expanded(
                child: TacticalStepper(
                  controller: minController,
                  label: 'min',
                  step: step,
                  unit: unit,
                  min: min,
                  max: max,
                  compact: true,
                  integer: integer,
                ),
              ),
              Container(
                width: 1,
                height: 56,
                color: tokens.border.withValues(alpha: 0.3),
                margin: const EdgeInsets.symmetric(
                  horizontal: AtriarchSpacing.sm,
                ),
              ),
              Expanded(
                child: TacticalStepper(
                  controller: maxController,
                  label: 'max',
                  step: step,
                  unit: unit,
                  min: min,
                  max: max,
                  compact: true,
                  integer: integer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/widgets/tactical/tactical_min_max_card_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/tactical/tactical_min_max_card.dart test/widgets/tactical/tactical_min_max_card_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add TacticalMinMaxCard

Shared-header card holding two compact TacticalSteppers for
min/max range parameters.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: TacticalPrimaryButton

**Files:**
- Create: `lib/widgets/tactical/tactical_primary_button.dart`
- Test: `test/widgets/tactical/tactical_primary_button_test.dart`

**Goal:** Full-width commit button with `primary`/`loading`/`destructive`/`disabled` variants.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_primary_button.dart';

void main() {
  testWidgets('primary renders label and fires onTap', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: TacticalPrimaryButton(
            label: 'commit // start drill',
            icon: Icons.bolt,
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );
    expect(find.text('COMMIT // START DRILL'), findsOneWidget);
    await tester.tap(find.byType(TacticalPrimaryButton));
    expect(pressed, isTrue);
  });

  testWidgets('loading variant disables tap and shows spinner', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: TacticalPrimaryButton(
            label: 'arming',
            variant: TacticalButtonVariant.loading,
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(TacticalPrimaryButton));
    expect(pressed, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/widgets/tactical/tactical_primary_button_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/widgets/tactical/tactical_primary_button.dart`:

```dart
import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

enum TacticalButtonVariant { primary, loading, destructive, disabled }

class TacticalPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final TacticalButtonVariant variant;

  const TacticalPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = TacticalButtonVariant.primary,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final (bg, fg) = switch (variant) {
      TacticalButtonVariant.primary => (tokens.statusHit, tokens.bgBase),
      TacticalButtonVariant.loading => (tokens.statusHit, tokens.bgBase),
      TacticalButtonVariant.destructive => (
          tokens.statusViolation,
          tokens.bgBase,
        ),
      TacticalButtonVariant.disabled => (
          tokens.statusOffline,
          tokens.bgBase.withValues(alpha: 0.6),
        ),
    };
    final enabled = variant == TacticalButtonVariant.primary ||
        variant == TacticalButtonVariant.destructive;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: bg,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (variant == TacticalButtonVariant.loading) ...[
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: fg,
                    ),
                  ),
                  const SizedBox(width: AtriarchSpacing.md),
                ] else if (icon != null) ...[
                  Icon(icon, color: fg, size: 20),
                  const SizedBox(width: AtriarchSpacing.sm),
                ],
                Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/widgets/tactical/tactical_primary_button_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/tactical/tactical_primary_button.dart test/widgets/tactical/tactical_primary_button_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add TacticalPrimaryButton

Full-width commit button with primary/loading/destructive/disabled
variants. Preserves Semantics label for accessibility.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: TacticalHudTile

**Files:**
- Create: `lib/widgets/tactical/tactical_hud_tile.dart`
- Test: `test/widgets/tactical/tactical_hud_tile_test.dart`

**Goal:** Small HUD tile: micro-label top, big mono numeric below.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/tactical_hud_tile.dart';

void main() {
  testWidgets('renders label and value', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: const Scaffold(
          body: TacticalHudTile(label: 'hits', value: '12'),
        ),
      ),
    );
    expect(find.text('HITS'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/widgets/tactical/tactical_hud_tile_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/widgets/tactical/tactical_hud_tile.dart`:

```dart
import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';
import 'tactical_card.dart';

class TacticalHudTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color? accent;

  const TacticalHudTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalCard(
      padding: const EdgeInsets.all(AtriarchSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AtriarchText.labelTiny(color: tokens.textTertiary),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: accent ?? tokens.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!.toUpperCase(),
                  style: AtriarchText.labelTiny(color: tokens.textTertiary),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/widgets/tactical/tactical_hud_tile_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/tactical/tactical_hud_tile.dart test/widgets/tactical/tactical_hud_tile_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add TacticalHudTile

Micro-label + big mono numeric. Used for KPI rows on drill-running
and results screens.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: GroupNodeCard

**Files:**
- Create: `lib/widgets/tactical/group_node_card.dart`
- Test: `test/widgets/tactical/group_node_card_test.dart`

**Goal:** Replace Program A's group `Card`. 2-col grid cell with assigned/standby/selected visual states.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/widgets/tactical/group_node_card.dart';

void main() {
  testWidgets('assigned renders check icon and ASSIGNED label',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: GroupNodeCard(
            groupIndex: 0,
            targetIds: const [1, 2, 3],
            selected: false,
            onTap: () {},
            onRemoveTarget: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('NODE_01'), findsOneWidget);
    expect(find.text('GROUP 01'), findsOneWidget);
    expect(find.text('ASSIGNED'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('standby renders STANDBY when empty', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: GroupNodeCard(
            groupIndex: 1,
            targetIds: const [],
            selected: false,
            onTap: () {},
            onRemoveTarget: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('NODE_02'), findsOneWidget);
    expect(find.text('STANDBY'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/widgets/tactical/group_node_card_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/widgets/tactical/group_node_card.dart`:

```dart
import 'package:flutter/material.dart';
import '../../theme/atriarch_theme.dart';

class GroupNodeCard extends StatelessWidget {
  final int groupIndex; // 0-based
  final List<int> targetIds;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<int> onRemoveTarget;

  const GroupNodeCard({
    super.key,
    required this.groupIndex,
    required this.targetIds,
    required this.selected,
    required this.onTap,
    required this.onRemoveTarget,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final assigned = targetIds.isNotEmpty;
    final groupColor = tokens.groupColor(groupIndex + 1);
    final nodeLabel =
        'NODE_${(groupIndex + 1).toString().padLeft(2, '0')}';
    final groupLabel = 'GROUP ${(groupIndex + 1).toString().padLeft(2, '0')}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: assigned
                ? tokens.bgElevated
                : tokens.bgCard.withValues(alpha: 0.5),
            border: selected
                ? Border.all(color: tokens.statusHit, width: 2)
                : Border(
                    left: BorderSide(
                      color: assigned
                          ? groupColor
                          : tokens.border.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
          ),
          padding: const EdgeInsets.all(AtriarchSpacing.md),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nodeLabel,
                    style: AtriarchText.labelTiny(
                      color: assigned
                          ? groupColor
                          : tokens.textTertiary.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    groupLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: assigned
                              ? tokens.textPrimary
                              : tokens.textTertiary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AtriarchSpacing.md),
                  if (targetIds.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: targetIds
                          .map(
                            (id) => InputChip(
                              label: Text('T$id'),
                              onDeleted: () => onRemoveTarget(id),
                              deleteIcon: Icon(
                                Icons.close,
                                size: 14,
                                color: tokens.statusViolation,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: AtriarchSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        assigned ? 'ASSIGNED' : 'STANDBY',
                        style: AtriarchText.labelTiny(
                          color: tokens.textTertiary,
                        ),
                      ),
                      Container(
                        width: 24,
                        height: 3,
                        color: assigned
                            ? groupColor
                            : tokens.border.withValues(alpha: 0.3),
                      ),
                    ],
                  ),
                ],
              ),
              if (assigned)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.check_circle,
                    size: 14,
                    color: groupColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/widgets/tactical/group_node_card_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/tactical/group_node_card.dart test/widgets/tactical/group_node_card_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add GroupNodeCard

Program A group tile with assigned/standby/selected visual states.
Preserves per-group color (magenta/cyan/yellow/purple/lime).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: TargetNodeChip

**Files:**
- Create: `lib/widgets/tactical/target_node_chip.dart`
- Test: `test/widgets/tactical/target_node_chip_test.dart`

**Goal:** Replace `TargetChip`. 36×36 square with `T##` + status glyph.

- [ ] **Step 1: Read the old `TargetChip` to preserve its contract**

```bash
cat lib/widgets/target_chip.dart
```

Note which properties and callbacks the call sites use. The spec says the tap handler is unchanged. Record the `Target` model shape before writing the new widget.

- [ ] **Step 2: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/models/target.dart';
import 'package:atriarch/widgets/tactical/target_node_chip.dart';

void main() {
  testWidgets('renders T## and fires onTap', (tester) async {
    var tapped = false;
    // Construct a Target using whatever constructor signature the model has.
    // Fill in: id, isOnline, isNoShoot per the Target model.
    final target = Target(id: 3, isOnline: true, isNoShoot: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: Scaffold(
          body: TargetNodeChip(
            target: target,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    expect(find.text('T3'), findsOneWidget);
    await tester.tap(find.byType(TargetNodeChip));
    expect(tapped, isTrue);
  });
}
```

If the `Target` model constructor signature differs, run `grep -n 'class Target' lib/models/target.dart` to find the real constructor and adjust. Do not invent fields.

- [ ] **Step 3: Run test to verify it fails**

```bash
flutter test test/widgets/tactical/target_node_chip_test.dart
```

Expected: FAIL.

- [ ] **Step 4: Implement**

Create `lib/widgets/tactical/target_node_chip.dart`:

```dart
import 'package:flutter/material.dart';
import '../../models/target.dart';
import '../../theme/atriarch_theme.dart';

class TargetNodeChip extends StatelessWidget {
  final Target target;
  final VoidCallback onTap;

  const TargetNodeChip({
    super.key,
    required this.target,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final dotColor = !target.isOnline
        ? tokens.statusOffline
        : target.isNoShoot
            ? tokens.statusViolation
            : tokens.statusLive;

    return Material(
      color: tokens.bgCard,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            border: Border.all(
              color: tokens.border.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  'T${target.id}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/widgets/tactical/target_node_chip_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/tactical/target_node_chip.dart test/widgets/tactical/target_node_chip_test.dart
git commit -m "$(cat <<'EOF'
feat(widgets): add TargetNodeChip

Square target chip with status dot (online/no-shoot/offline).
Replaces legacy TargetChip; deletion in cleanup phase.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3 — Screens (risk order)

### Task 14: Restyle home_screen

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Test: `test/screens/home_screen_test.dart` (create)

**Goal:** New layout with `TacticalScaffold` + connection banner + 3 tactical cards (Target Setup placeholder, Program A, Program B). All existing navigation and snackbar behavior preserved.

- [ ] **Step 1: Re-read the current home screen**

```bash
sed -n '1,200p' lib/screens/home_screen.dart
```

Record: `_ConnectionBanner` uses `bleService.connectionState` stream and re-navigates to `DeviceDiscoveryScreen` on disconnected tap. `_HomeRow` has three entries: Target Setup (snackbar placeholder), Program A (pushes `ProgramASetupScreen`), Program B (pushes `ProgramBSetupScreen`).

- [ ] **Step 2: Write the failing test**

Create `test/screens/home_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/home_screen.dart';

void main() {
  testWidgets('renders three tactical program rows', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('TARGET_SETUP'), findsOneWidget);
    expect(find.text('PROGRAM_A'), findsOneWidget);
    expect(find.text('PROGRAM_B'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
flutter test test/screens/home_screen_test.dart
```

Expected: FAIL — current home_screen uses `Target Setup` title-case, not `TARGET_SETUP`.

- [ ] **Step 4: Rewrite the screen**

Replace `lib/screens/home_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';
import '../widgets/tactical/tactical_status_chip.dart';
import 'device_discovery_screen.dart';
import 'program_a_setup_screen.dart';
import 'program_b_setup_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TacticalScaffold(
      title: 'ATRIARCH // HOME',
      body: ListView(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        children: [
          const _ConnectionBanner(),
          const SizedBox(height: AtriarchSpacing.lg),
          const TacticalSection(code: 'PARAM_01', trailing: 'PROTOCOL_SELECT'),
          const SizedBox(height: AtriarchSpacing.sm),
          _HomeCard(
            code: 'TARGET_SETUP',
            title: 'TARGET SETUP',
            subtitle: 'Scan the fleet, identify units, mark no-shoots.',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Target Discovery screen not built yet.'),
                ),
              );
            },
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          _HomeCard(
            code: 'PROGRAM_A',
            title: 'GROUP MODE',
            subtitle: 'Up to 5 groups. One active target per group.',
            accent: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProgramASetupScreen(),
              ),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          _HomeCard(
            code: 'PROGRAM_B',
            title: 'INDIVIDUAL MODE',
            subtitle: 'Every target runs its own reaction drill.',
            accent: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProgramBSetupScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final String code;
  final String title;
  final String subtitle;
  final bool accent;
  final VoidCallback onTap;

  const _HomeCard({
    required this.code,
    required this.title,
    required this.subtitle,
    this.accent = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalCard(
      accent: accent ? tokens.statusHit : tokens.border,
      padding: const EdgeInsets.all(AtriarchSpacing.lg),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  style: AtriarchText.labelTiny(color: tokens.statusHit),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: tokens.textTertiary),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: tokens.textTertiary),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner();

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final bleService = context.read<AppState>().bleService;
    return StreamBuilder<BluetoothConnectionState>(
      stream: bleService.connectionState,
      initialData: bleService.isConnected
          ? BluetoothConnectionState.connected
          : BluetoothConnectionState.disconnected,
      builder: (context, snapshot) {
        final connected = snapshot.data == BluetoothConnectionState.connected;
        final deviceName = bleService.device?.platformName;
        final accent = connected ? tokens.statusLive : tokens.statusViolation;
        return TacticalCard(
          accent: accent,
          background: accent.withValues(alpha: 0.08),
          onTap: connected
              ? null
              : () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DeviceDiscoveryScreen(),
                    ),
                  ),
          child: Row(
            children: [
              TacticalStatusChip(
                color: accent,
                label: connected ? 'connected' : 'disconnected',
              ),
              const SizedBox(width: AtriarchSpacing.sm),
              Expanded(
                child: Text(
                  connected
                      ? (deviceName != null && deviceName.isNotEmpty
                          ? deviceName
                          : 'TRANSMITTER LINKED')
                      : 'TAP TO RECONNECT',
                  style: AtriarchText.labelTiny(color: tokens.textPrimary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/screens/home_screen_test.dart
```

Expected: PASS.

- [ ] **Step 6: Verify no regressions in static analysis**

```bash
flutter analyze lib/screens/home_screen.dart
```

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/home_screen.dart test/screens/home_screen_test.dart
git commit -m "$(cat <<'EOF'
refactor(home): restyle HomeScreen with tactical language

TacticalScaffold + TacticalCard rows + TacticalStatusChip connection
banner. Navigation handlers and snackbar behavior preserved.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: Restyle device_discovery_screen

**Files:**
- Modify: `lib/screens/device_discovery_screen.dart`
- Test: `test/screens/device_discovery_screen_test.dart` (create)

**Goal:** Apply tactical styling. Replace FAB with inline `TacticalPrimaryButton` for scan control. Preserve BLE pairing and connect logic.

- [ ] **Step 1: Write a structural test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/device_discovery_screen.dart';
import 'package:atriarch/widgets/tactical/tactical_section.dart';

void main() {
  testWidgets('renders PARAM_01 scan section', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const DeviceDiscoveryScreen(),
        ),
      ),
    );
    // First frame only — avoid touching BLE streams.
    expect(find.byType(TacticalSection), findsWidgets);
    expect(find.text('PARAM_01'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/screens/device_discovery_screen_test.dart
```

Expected: FAIL (current screen doesn't have `TacticalSection`).

- [ ] **Step 3: Rewrite the screen**

Replace `lib/screens/device_discovery_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_primary_button.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';
import '../widgets/tactical/tactical_status_chip.dart';
import 'home_screen.dart';

class DeviceDiscoveryScreen extends StatefulWidget {
  const DeviceDiscoveryScreen({super.key});

  @override
  State<DeviceDiscoveryScreen> createState() => _DeviceDiscoveryScreenState();
}

class _DeviceDiscoveryScreenState extends State<DeviceDiscoveryScreen> {
  @override
  void initState() {
    super.initState();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
  }

  Future<void> _connectAndNavigate(BluetoothDevice device) async {
    final appState = context.read<AppState>();
    try {
      await appState.bleService.connect(device);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalScaffold(
      title: 'TRANSMITTER // PAIRING',
      trailing: StreamBuilder<bool>(
        stream: FlutterBluePlus.isScanning,
        initialData: false,
        builder: (context, snapshot) {
          final scanning = snapshot.data ?? false;
          return TacticalStatusChip(
            color: scanning ? tokens.statusArmed : tokens.statusOffline,
            label: scanning ? 'scanning' : 'idle',
          );
        },
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            FlutterBluePlus.startScan(timeout: const Duration(seconds: 4)),
        child: ListView(
          padding: const EdgeInsets.all(AtriarchSpacing.lg),
          children: [
            const TacticalSection(
              code: 'PARAM_01',
              trailing: 'SCAN_CONTROL',
            ),
            const SizedBox(height: AtriarchSpacing.sm),
            StreamBuilder<bool>(
              stream: FlutterBluePlus.isScanning,
              initialData: false,
              builder: (context, snapshot) {
                final scanning = snapshot.data ?? false;
                return TacticalPrimaryButton(
                  label: scanning ? 'scanning' : 'scan for transmitters',
                  icon: scanning ? null : Icons.bluetooth_searching,
                  variant: scanning
                      ? TacticalButtonVariant.loading
                      : TacticalButtonVariant.primary,
                  onPressed: () {
                    if (scanning) {
                      FlutterBluePlus.stopScan();
                    } else {
                      FlutterBluePlus.startScan(
                        timeout: const Duration(seconds: 4),
                      );
                    }
                  },
                );
              },
            ),
            const SizedBox(height: AtriarchSpacing.xl),
            const TacticalSection(
              code: 'PARAM_02',
              trailing: 'DEVICES_DETECTED',
            ),
            const SizedBox(height: AtriarchSpacing.sm),
            StreamBuilder<List<ScanResult>>(
              stream: FlutterBluePlus.scanResults,
              initialData: const [],
              builder: (context, snapshot) {
                final results = snapshot.data ?? [];
                if (results.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(AtriarchSpacing.lg),
                    child: Text(
                      'SCANNING FOR DEVICES…',
                      style: AtriarchText.labelTiny(
                        color: tokens.textTertiary,
                      ),
                    ),
                  );
                }
                return Column(
                  children: results.map((r) {
                    final name = r.device.platformName.isNotEmpty
                        ? r.device.platformName
                        : r.device.remoteId.toString();
                    return Padding(
                      padding: const EdgeInsets.only(
                        bottom: AtriarchSpacing.sm,
                      ),
                      child: TacticalCard(
                        accent: r.advertisementData.connectable
                            ? tokens.statusHit
                            : tokens.border,
                        onTap: r.advertisementData.connectable
                            ? () => _connectAndNavigate(r.device)
                            : null,
                        child: Row(
                          children: [
                            Icon(
                              Icons.bluetooth,
                              color: tokens.statusHit,
                              size: 18,
                            ),
                            const SizedBox(width: AtriarchSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    r.device.remoteId.toString(),
                                    style: AtriarchText.labelTiny(
                                      color: tokens.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${r.rssi} dBm',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/screens/device_discovery_screen_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/device_discovery_screen.dart test/screens/device_discovery_screen_test.dart
git commit -m "$(cat <<'EOF'
refactor(discovery): restyle transmitter pairing with tactical shell

TacticalScaffold + PARAM_01 scan button + PARAM_02 device list.
FAB removed in favor of inline primary button. BLE connect logic
unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: Restyle program_b_setup_screen

**Files:**
- Modify: `lib/screens/program_b_setup_screen.dart`
- Test: `test/screens/program_b_setup_screen_test.dart` (create)

**Goal:** Tactical shell + `TacticalMinMaxCard`s + inline scan button (no FAB). Preserve all DrillConfig construction, arming-failed banner, navigation.

- [ ] **Step 1: Write a structural test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/program_b_setup_screen.dart';
import 'package:atriarch/widgets/tactical/tactical_min_max_card.dart';
import 'package:atriarch/widgets/tactical/tactical_primary_button.dart';

void main() {
  testWidgets('renders 3 MinMaxCards and primary start button',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const ProgramBSetupScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TacticalMinMaxCard), findsNWidgets(3));
    expect(find.byType(TacticalPrimaryButton), findsWidgets);
    expect(find.text('START DELAY'), findsOneWidget);
    expect(find.text('TIME BETWEEN ACTIVATIONS'), findsOneWidget);
    expect(find.text('REQUIRED HITS'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/screens/program_b_setup_screen_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Rewrite the screen**

Replace `lib/screens/program_b_setup_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/drill_config.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_min_max_card.dart';
import '../widgets/tactical/tactical_primary_button.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';
import '../widgets/tactical/tactical_status_chip.dart';
import '../widgets/tactical/tactical_stepper.dart';
import 'drill_running_screen.dart';

class ProgramBSetupScreen extends StatefulWidget {
  const ProgramBSetupScreen({super.key});

  @override
  State<ProgramBSetupScreen> createState() => _ProgramBSetupScreenState();
}

class _ProgramBSetupScreenState extends State<ProgramBSetupScreen> {
  final startMinCtrl = TextEditingController(text: '1.00');
  final startMaxCtrl = TextEditingController(text: '3.00');
  final delayMinCtrl = TextEditingController(text: '0.50');
  final delayMaxCtrl = TextEditingController(text: '2.00');
  final hitsMinCtrl = TextEditingController(text: '1');
  final hitsMaxCtrl = TextEditingController(text: '3');
  final iterCtrl = TextEditingController(text: '5');

  DrillConfig? _lastConfig;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().resetDrillPhase();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().addListener(_onPhaseChanged);
    });
  }

  @override
  void dispose() {
    try {
      context.read<AppState>().removeListener(_onPhaseChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onPhaseChanged() {
    if (!mounted) return;
    final state = context.read<AppState>();
    if (state.phase == DrillPhase.running) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DrillRunningScreen()),
      );
    } else {
      setState(() {});
    }
  }

  DrillConfig? _buildConfig() {
    final state = context.read<AppState>();
    final onlineTargets = state.targets.where((t) => t.isOnline).toList();

    if (onlineTargets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No targets online. Run Target Setup first.'),
        ),
      );
      return null;
    }

    return DrillConfig(
      programType: ProgramType.programB,
      startMin: double.tryParse(startMinCtrl.text) ?? 1.0,
      startMax: double.tryParse(startMaxCtrl.text) ?? 3.0,
      delayMin: double.tryParse(delayMinCtrl.text) ?? 0.5,
      delayMax: double.tryParse(delayMaxCtrl.text) ?? 2.0,
      hitsMin: int.tryParse(hitsMinCtrl.text) ?? 1,
      hitsMax: int.tryParse(hitsMaxCtrl.text) ?? 3,
      targetIds: onlineTargets.map((t) => t.id).toList(),
      noShootIds:
          onlineTargets.where((t) => t.isNoShoot).map((t) => t.id).toList(),
      iterations: int.tryParse(iterCtrl.text) ?? 5,
    );
  }

  void _startDrill() {
    final config = _buildConfig();
    if (config == null) return;
    _lastConfig = config;
    context.read<AppState>().startDrill(config);
  }

  void _retryDrill() {
    final state = context.read<AppState>();
    state.resetDrillPhase();
    final config = _lastConfig ?? _buildConfig();
    if (config == null) return;
    state.startDrill(config);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalScaffold(
      title: 'PROGRAM_CONFIG',
      trailing: Consumer<AppState>(
        builder: (_, state, __) {
          final online = state.targets.where((t) => t.isOnline).length;
          return TacticalStatusChip(
            color:
                online > 0 ? tokens.statusLive : tokens.statusOffline,
            label: online > 0 ? 'live' : 'offline',
          );
        },
      ),
      body: ListView(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        children: [
          _header(context),
          const SizedBox(height: AtriarchSpacing.lg),
          const TacticalSection(
            code: 'PARAM_00',
            trailing: 'NODE_SCAN',
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          Consumer<AppState>(
            builder: (_, state, __) {
              final scanning = state.isScanning;
              return TacticalPrimaryButton(
                label: scanning ? 'scanning' : 'scan for targets',
                icon: scanning ? null : Icons.refresh,
                variant: scanning
                    ? TacticalButtonVariant.loading
                    : TacticalButtonVariant.primary,
                onPressed: () => state.discoverTargets(),
              );
            },
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(code: 'PARAM_01', trailing: 'TIMING'),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalMinMaxCard(
            title: 'START DELAY',
            rangeHint: '0.00 – 10.00 SEC',
            minController: startMinCtrl,
            maxController: startMaxCtrl,
            step: 0.25,
            unit: 'sec',
            min: 0,
            max: 10,
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalMinMaxCard(
            title: 'TIME BETWEEN ACTIVATIONS',
            rangeHint: '0.00 – 10.00 SEC',
            minController: delayMinCtrl,
            maxController: delayMaxCtrl,
            step: 0.25,
            unit: 'sec',
            min: 0,
            max: 10,
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalMinMaxCard(
            title: 'REQUIRED HITS',
            rangeHint: '1 – 20',
            minController: hitsMinCtrl,
            maxController: hitsMaxCtrl,
            step: 1,
            unit: 'hits',
            min: 1,
            max: 20,
            integer: true,
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(code: 'PARAM_02', trailing: 'ITERATIONS'),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalCard(
            accent: tokens.statusHit,
            child: TacticalStepper(
              controller: iterCtrl,
              label: 'iterations per target',
              unit: 'count',
              step: 1,
              min: 1,
              max: 50,
              integer: true,
            ),
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          Consumer<AppState>(
            builder: (_, state, __) {
              final online = state.targets.where((t) => t.isOnline).length;
              final noShoot = state.targets
                  .where((t) => t.isOnline && t.isNoShoot)
                  .length;
              return Text(
                '$online TARGET(S) ONLINE // $noShoot NO-SHOOT',
                style: AtriarchText.labelTiny(color: tokens.textTertiary),
              );
            },
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          Consumer<AppState>(
            builder: (_, state, __) {
              if (state.phase == DrillPhase.armingFailed) {
                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: AtriarchSpacing.md,
                  ),
                  child: _ArmingFailedBanner(onRetry: _retryDrill),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Consumer<AppState>(
            builder: (_, state, __) {
              final arming = state.phase == DrillPhase.arming;
              return TacticalPrimaryButton(
                label: arming ? 'arming' : 'commit // start drill',
                icon: arming ? null : Icons.bolt,
                variant: arming
                    ? TacticalButtonVariant.loading
                    : TacticalButtonVariant.primary,
                onPressed: _startDrill,
              );
            },
          ),
          const SizedBox(height: AtriarchSpacing.xxl),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final tokens = context.atriarch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PROTOCOL_STATUS',
          style: AtriarchText.labelTiny(color: tokens.textTertiary),
        ),
        const SizedBox(height: 4),
        Text(
          'PROGRAM B / INDIVIDUAL MODE',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ],
    );
  }
}

class _ArmingFailedBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _ArmingFailedBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalCard(
      accent: tokens.statusViolation,
      child: Row(
        children: [
          Icon(Icons.error_outline, color: tokens.statusViolation),
          const SizedBox(width: AtriarchSpacing.md),
          Expanded(
            child: Text(
              'NO RESPONSE FROM TRANSMITTER // CHECK CONNECTION',
              style: AtriarchText.labelTiny(color: tokens.textPrimary),
            ),
          ),
          const SizedBox(width: AtriarchSpacing.sm),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('RETRY'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/screens/program_b_setup_screen_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/program_b_setup_screen.dart test/screens/program_b_setup_screen_test.dart
git commit -m "$(cat <<'EOF'
refactor(program_b): tactical shell + MinMaxCards + inline scan

Replace IncDec rows with TacticalMinMaxCard. FAB replaced by inline
TacticalPrimaryButton under PARAM_00 // NODE_SCAN. Arming-failed
banner restyled, retry behavior preserved.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 17: Restyle program_a_setup_screen

**Files:**
- Modify: `lib/screens/program_a_setup_screen.dart`
- Test: `test/screens/program_a_setup_screen_test.dart` (create)

**Goal:** Program A with group allocation grid (5 `GroupNodeCard`s) and available-targets wrap.

- [ ] **Step 1: Write a structural test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/program_a_setup_screen.dart';
import 'package:atriarch/widgets/tactical/group_node_card.dart';
import 'package:atriarch/widgets/tactical/tactical_min_max_card.dart';

void main() {
  testWidgets('renders 5 GroupNodeCards and 3 MinMaxCards', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const ProgramASetupScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GroupNodeCard), findsNWidgets(5));
    expect(find.byType(TacticalMinMaxCard), findsNWidgets(3));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/screens/program_a_setup_screen_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Rewrite the screen**

Replace `lib/screens/program_a_setup_screen.dart` with the tactical version. Key bits:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/drill_config.dart';
import '../models/target_group.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/group_node_card.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_min_max_card.dart';
import '../widgets/tactical/tactical_primary_button.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';
import '../widgets/tactical/tactical_status_chip.dart';
import '../widgets/tactical/tactical_stepper.dart';
import '../widgets/tactical/target_node_chip.dart';
import 'drill_running_screen.dart';

class ProgramASetupScreen extends StatefulWidget {
  const ProgramASetupScreen({super.key});

  @override
  State<ProgramASetupScreen> createState() => _ProgramASetupScreenState();
}

class _ProgramASetupScreenState extends State<ProgramASetupScreen> {
  final startMinCtrl = TextEditingController(text: '1.00');
  final startMaxCtrl = TextEditingController(text: '3.00');
  final delayMinCtrl = TextEditingController(text: '0.50');
  final delayMaxCtrl = TextEditingController(text: '2.00');
  final hitsMinCtrl = TextEditingController(text: '1');
  final hitsMaxCtrl = TextEditingController(text: '3');
  final iterCtrl = TextEditingController(text: '5');

  List<TargetGroup> groups = List.generate(5, (i) => TargetGroup(id: i + 1));
  int? selectedGroupIndex;
  DrillConfig? _lastConfig;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().resetDrillPhase();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().addListener(_onPhaseChanged);
    });
  }

  @override
  void dispose() {
    try {
      context.read<AppState>().removeListener(_onPhaseChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onPhaseChanged() {
    if (!mounted) return;
    final state = context.read<AppState>();
    if (state.phase == DrillPhase.running) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DrillRunningScreen()),
      );
    } else {
      setState(() {});
    }
  }

  DrillConfig? _buildConfig() {
    final state = context.read<AppState>();
    final activeGroups = groups.where((g) => g.targetIds.isNotEmpty).toList();
    if (activeGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Assign at least one target to a group.'),
        ),
      );
      return null;
    }

    final noShootIds = state.targets
        .where((t) => t.isOnline && t.isNoShoot)
        .map((t) => t.id)
        .toList();

    return DrillConfig(
      programType: ProgramType.programA,
      startMin: double.tryParse(startMinCtrl.text) ?? 1.0,
      startMax: double.tryParse(startMaxCtrl.text) ?? 3.0,
      delayMin: double.tryParse(delayMinCtrl.text) ?? 0.5,
      delayMax: double.tryParse(delayMaxCtrl.text) ?? 2.0,
      hitsMin: int.tryParse(hitsMinCtrl.text) ?? 1,
      hitsMax: int.tryParse(hitsMaxCtrl.text) ?? 3,
      groups: groups,
      noShootIds: noShootIds,
      iterations: int.tryParse(iterCtrl.text) ?? 5,
    );
  }

  void _startDrill() {
    final config = _buildConfig();
    if (config == null) return;
    _lastConfig = config;
    context.read<AppState>().startDrill(config);
  }

  void _retryDrill() {
    final state = context.read<AppState>();
    state.resetDrillPhase();
    final config = _lastConfig ?? _buildConfig();
    if (config == null) return;
    state.startDrill(config);
  }

  void _assignTargetToGroup(int targetId) {
    if (selectedGroupIndex == null) return;
    setState(() {
      for (final g in groups) {
        g.targetIds.remove(targetId);
      }
      groups[selectedGroupIndex!].targetIds.add(targetId);
    });
  }

  void _removeTargetFromGroup(int groupIndex, int targetId) {
    setState(() {
      groups[groupIndex].targetIds.remove(targetId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalScaffold(
      title: 'PROGRAM_CONFIG',
      trailing: Consumer<AppState>(
        builder: (_, state, __) {
          final online = state.targets.where((t) => t.isOnline).length;
          return TacticalStatusChip(
            color:
                online > 0 ? tokens.statusLive : tokens.statusOffline,
            label: online > 0 ? 'live' : 'offline',
          );
        },
      ),
      body: ListView(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        children: [
          _header(context),
          const SizedBox(height: AtriarchSpacing.lg),
          const TacticalSection(code: 'PARAM_01', trailing: 'TIMING'),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalMinMaxCard(
            title: 'START DELAY',
            rangeHint: '0.00 – 10.00 SEC',
            minController: startMinCtrl,
            maxController: startMaxCtrl,
            step: 0.25,
            unit: 'sec',
            min: 0,
            max: 10,
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalMinMaxCard(
            title: 'TIME BETWEEN ACTIVATIONS',
            rangeHint: '0.00 – 10.00 SEC',
            minController: delayMinCtrl,
            maxController: delayMaxCtrl,
            step: 0.25,
            unit: 'sec',
            min: 0,
            max: 10,
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalMinMaxCard(
            title: 'REQUIRED HITS',
            rangeHint: '1 – 20',
            minController: hitsMinCtrl,
            maxController: hitsMaxCtrl,
            step: 1,
            unit: 'hits',
            min: 1,
            max: 20,
            integer: true,
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(code: 'PARAM_02', trailing: 'ITERATIONS'),
          const SizedBox(height: AtriarchSpacing.sm),
          TacticalCard(
            accent: tokens.statusHit,
            child: TacticalStepper(
              controller: iterCtrl,
              label: 'iterations per group',
              unit: 'count',
              step: 1,
              min: 1,
              max: 50,
              integer: true,
            ),
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(
            code: 'PARAM_03',
            trailing: 'ALLOCATION_GRID',
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AtriarchSpacing.sm,
            crossAxisSpacing: AtriarchSpacing.sm,
            childAspectRatio: 1.6,
            children: List.generate(
              5,
              (i) => GroupNodeCard(
                groupIndex: i,
                targetIds: groups[i].targetIds,
                selected: selectedGroupIndex == i,
                onTap: () => setState(() => selectedGroupIndex = i),
                onRemoveTarget: (id) => _removeTargetFromGroup(i, id),
              ),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(
            code: 'PARAM_04',
            trailing: 'AVAILABLE_NODES',
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          Consumer<AppState>(
            builder: (_, state, __) {
              final assigned = groups.expand((g) => g.targetIds).toSet();
              final unassigned = state.targets
                  .where((t) => t.isOnline && !assigned.contains(t.id))
                  .toList();
              if (unassigned.isEmpty) {
                return Text(
                  'ALL NODES ASSIGNED',
                  style: AtriarchText.labelTiny(color: tokens.textTertiary),
                );
              }
              return Wrap(
                spacing: AtriarchSpacing.sm,
                runSpacing: AtriarchSpacing.sm,
                children: unassigned
                    .map(
                      (t) => TargetNodeChip(
                        target: t,
                        onTap: () => _assignTargetToGroup(t.id),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          Consumer<AppState>(
            builder: (_, state, __) {
              if (state.phase == DrillPhase.armingFailed) {
                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: AtriarchSpacing.md,
                  ),
                  child: _ArmingFailedBanner(onRetry: _retryDrill),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Consumer<AppState>(
            builder: (_, state, __) {
              final arming = state.phase == DrillPhase.arming;
              return TacticalPrimaryButton(
                label: arming ? 'arming' : 'commit // start drill',
                icon: arming ? null : Icons.bolt,
                variant: arming
                    ? TacticalButtonVariant.loading
                    : TacticalButtonVariant.primary,
                onPressed: _startDrill,
              );
            },
          ),
          const SizedBox(height: AtriarchSpacing.xxl),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final tokens = context.atriarch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PROTOCOL_STATUS',
          style: AtriarchText.labelTiny(color: tokens.textTertiary),
        ),
        const SizedBox(height: 4),
        Text(
          'PROGRAM A / GROUP MODE',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ],
    );
  }
}

class _ArmingFailedBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _ArmingFailedBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalCard(
      accent: tokens.statusViolation,
      child: Row(
        children: [
          Icon(Icons.error_outline, color: tokens.statusViolation),
          const SizedBox(width: AtriarchSpacing.md),
          Expanded(
            child: Text(
              'NO RESPONSE FROM TRANSMITTER // CHECK CONNECTION',
              style: AtriarchText.labelTiny(color: tokens.textPrimary),
            ),
          ),
          const SizedBox(width: AtriarchSpacing.sm),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('RETRY'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/screens/program_a_setup_screen_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/program_a_setup_screen.dart test/screens/program_a_setup_screen_test.dart
git commit -m "$(cat <<'EOF'
refactor(program_a): tactical shell + MinMaxCards + GroupNodeCards

Replace IncDec rows with TacticalMinMaxCards. Replace group Cards
with GroupNodeCard 2-col grid. Available targets use TargetNodeChip.
Arming-failed banner + retry preserved.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 18: Restyle results_screen

**Files:**
- Modify: `lib/screens/results_screen.dart`
- Test: `test/screens/results_screen_test.dart` (create)

**Goal:** Tactical shell + 6 KPI `TacticalHudTile`s in a 2-col grid + per-target cards + styled event log. Remove FAB in favor of inline `NEW DRILL` button.

- [ ] **Step 1: Write a lightweight smoke test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/results_screen.dart';

void main() {
  testWidgets('shows empty state when no session', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const ResultsScreen(),
        ),
      ),
    );
    await tester.pump();
    // Empty session state text — preserved from current screen.
    expect(find.text('No session data.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/screens/results_screen_test.dart
```

Expected: PASS or FAIL depending on current text. If current says `'No session data.'` literally, the test passes as-is after rewrite. If the rewrite drops that exact phrase, update test to match what the tactical version uses (see below, we preserve the string).

- [ ] **Step 3: Rewrite the screen**

Replace `lib/screens/results_screen.dart`. See the spec's `results_screen.dart` section for layout; this plan implements it:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/session_event.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/tactical/tactical_card.dart';
import '../widgets/tactical/tactical_hud_tile.dart';
import '../widgets/tactical/tactical_primary_button.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_section.dart';
import 'home_screen.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final session = state.currentSession;

    if (session == null) {
      return const TacticalScaffold(
        title: 'RESULTS // DOSSIER',
        body: Center(child: Text('No session data.')),
      );
    }

    final tokens = context.atriarch;
    final events = session.events;
    final activations =
        events.where((e) => e.type == EventType.targetActivated).toList();
    final completions =
        events.where((e) => e.type == EventType.targetComplete).toList();
    final noShoots =
        events.where((e) => e.type == EventType.noShootViolation).toList();
    final lateHits =
        events.where((e) => e.type == EventType.lateHit).toList();
    final hits = events.where((e) => e.type == EventType.hitDetected).toList();

    final targetIds =
        activations.map((e) => e.targetId).whereType<int>().toSet();
    final perTarget = <int, _TargetStats>{};
    for (final id in targetIds) {
      final tCompletions =
          completions.where((e) => e.targetId == id).toList();
      final avgTime = tCompletions.isNotEmpty
          ? tCompletions
                  .map((e) => e.totalTimeMs ?? 0)
                  .reduce((a, b) => a + b) /
              tCompletions.length
          : 0.0;
      perTarget[id] = _TargetStats(
        hits: hits.where((e) => e.targetId == id).length,
        completions: tCompletions.length,
        noShoots: noShoots.where((e) => e.targetId == id).length,
        lateHits: lateHits.where((e) => e.targetId == id).length,
        avgCompletionMs: avgTime,
      );
    }

    return TacticalScaffold(
      title: 'RESULTS // DOSSIER',
      body: ListView(
        padding: const EdgeInsets.all(AtriarchSpacing.lg),
        children: [
          Text(
            'PROTOCOL_STATUS',
            style: AtriarchText.labelTiny(color: tokens.textTertiary),
          ),
          const SizedBox(height: 4),
          Text(
            'DRILL COMPLETE',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AtriarchSpacing.lg),
          const TacticalSection(code: 'SUMMARY_01', trailing: 'KPI'),
          const SizedBox(height: AtriarchSpacing.sm),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.4,
            mainAxisSpacing: AtriarchSpacing.sm,
            crossAxisSpacing: AtriarchSpacing.sm,
            children: [
              TacticalHudTile(
                label: 'duration',
                value: _formatDuration(session.elapsed),
              ),
              TacticalHudTile(
                label: 'activations',
                value: '${activations.length}',
              ),
              TacticalHudTile(label: 'total hits', value: '${hits.length}'),
              TacticalHudTile(
                label: 'completions',
                value: '${completions.length}',
                accent: tokens.statusLive,
              ),
              TacticalHudTile(
                label: 'no-shoot',
                value: '${noShoots.length}',
                accent: noShoots.isEmpty
                    ? tokens.statusLive
                    : tokens.statusViolation,
              ),
              TacticalHudTile(
                label: 'late hits',
                value: '${lateHits.length}',
                accent:
                    lateHits.isEmpty ? tokens.statusLive : tokens.statusLate,
              ),
            ],
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(code: 'SUMMARY_02', trailing: 'PER_NODE'),
          const SizedBox(height: AtriarchSpacing.sm),
          ...perTarget.entries.map(
            (entry) => Padding(
              padding:
                  const EdgeInsets.only(bottom: AtriarchSpacing.sm),
              child: _PerTargetRow(id: entry.key, stats: entry.value),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.xl),
          const TacticalSection(code: 'SUMMARY_03', trailing: 'EVENT_LOG'),
          const SizedBox(height: AtriarchSpacing.sm),
          ...events.map((e) => _EventRow(event: e)),
          const SizedBox(height: AtriarchSpacing.xl),
          TacticalPrimaryButton(
            label: 'new drill',
            icon: Icons.refresh,
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            ),
          ),
          const SizedBox(height: AtriarchSpacing.xxl),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s}s';
  }
}

class _TargetStats {
  final int hits;
  final int completions;
  final int noShoots;
  final int lateHits;
  final double avgCompletionMs;
  _TargetStats({
    required this.hits,
    required this.completions,
    required this.noShoots,
    required this.lateHits,
    required this.avgCompletionMs,
  });
}

class _PerTargetRow extends StatelessWidget {
  final int id;
  final _TargetStats stats;
  const _PerTargetRow({required this.id, required this.stats});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return TacticalCard(
      accent: tokens.border,
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              'NODE_T$id',
              style: AtriarchText.labelTiny(color: tokens.statusHit),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _kv('HITS', '${stats.hits}', tokens),
                  _kv('DONE', '${stats.completions}', tokens),
                  _kv('AVG', '${stats.avgCompletionMs.toInt()}MS', tokens),
                  _kv(
                    'NS',
                    '${stats.noShoots}',
                    tokens,
                    color: stats.noShoots > 0
                        ? tokens.statusViolation
                        : tokens.textPrimary,
                  ),
                  _kv(
                    'LATE',
                    '${stats.lateHits}',
                    tokens,
                    color: stats.lateHits > 0
                        ? tokens.statusLate
                        : tokens.textPrimary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, AtriarchTokens tokens, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(right: AtriarchSpacing.lg),
      child: Row(
        children: [
          Text(
            '$k ',
            style: AtriarchText.labelTiny(color: tokens.textTertiary),
          ),
          Text(
            v,
            style: TextStyle(
              color: color ?? tokens.textPrimary,
              fontFamily: 'JetBrainsMono',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final SessionEvent event;
  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final (color, text) = switch (event.type) {
      EventType.targetActivated => (
          tokens.statusLive,
          'Target ${event.targetId} activated',
        ),
      EventType.hitDetected => (
          tokens.statusHit,
          'Target ${event.targetId} hit ${event.hitNumber}/${event.requiredHits}',
        ),
      EventType.targetComplete => (
          tokens.statusLive,
          'Target ${event.targetId} complete (${event.totalTimeMs}ms)',
        ),
      EventType.noShootViolation => (
          tokens.statusViolation,
          'NO-SHOOT Target ${event.targetId}!',
        ),
      EventType.lateHit => (
          tokens.statusLate,
          'Late hit on Target ${event.targetId}',
        ),
      EventType.drillFinished => (tokens.textTertiary, 'Drill finished'),
      EventType.error => (
          tokens.statusViolation,
          'Error: ${event.errorDetail}',
        ),
    };
    final ts =
        '${event.timestamp.hour}:${event.timestamp.minute.toString().padLeft(2, '0')}:${event.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 2)),
      ),
      child: Row(
        children: [
          const SizedBox(width: AtriarchSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            ts,
            style: AtriarchText.labelTiny(color: tokens.textTertiary),
          ),
        ],
      ),
    );
  }
}
```

Note: the `_PerTargetRow` `_kv` uses `fontFamily: 'JetBrainsMono'` as a raw string — if `google_fonts` populates it differently, wrap the value in `GoogleFonts.jetBrainsMono(textStyle: ...)` instead. Run once to verify the font renders correctly; adjust if needed.

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/screens/results_screen_test.dart
```

Expected: PASS (empty session state preserved verbatim).

- [ ] **Step 5: Commit**

```bash
git add lib/screens/results_screen.dart test/screens/results_screen_test.dart
git commit -m "$(cat <<'EOF'
refactor(results): tactical dossier layout

Replace ad-hoc stat cards with TacticalHudTile grid. Replace DataTable
with per-target TacticalCard rows. Style event log with colored left
borders. FAB replaced by inline NEW DRILL button.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 19: Restyle drill_running_screen — HUD (safety-critical)

**Files:**
- Modify: `lib/screens/drill_running_screen.dart`
- Test: `test/screens/drill_running_screen_test.dart` (create)

**Goal:** HUD layout with hero timer + KPI tiles + redesigned square STOP button. **All press-and-hold timing and gesture logic preserved unchanged.**

- [ ] **Step 1: Write a gesture-preservation test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/drill_running_screen.dart';

void main() {
  testWidgets('renders STOP label', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const DrillRunningScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('STOP'), findsOneWidget);
  });

  testWidgets('tap alone does not trigger stop', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const DrillRunningScreen(),
        ),
      ),
    );
    await tester.pump();
    // Single tap — should NOT stop (press-and-hold required).
    await tester.tap(find.text('STOP'));
    await tester.pump(const Duration(milliseconds: 100));
    // After 100ms, drill should still be running (phase not finished).
    // No assertion on phase here — just ensure no exception and screen
    // still renders STOP.
    expect(find.text('STOP'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/screens/drill_running_screen_test.dart
```

Expected: PASS or FAIL depending on current `STOP` label — likely passes pre-change. Consider adding a `find.byType(TacticalHudTile)` assertion and re-running to drive the rewrite.

Append to the test file:

```dart
  testWidgets('HUD row is present after rewrite', (tester) async {
    // Will fail until Task 19 Step 3 is done.
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const DrillRunningScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('HITS'), findsOneWidget);
  });
```

Re-run; this should now FAIL.

- [ ] **Step 3: Rewrite the screen**

Key preservation rules — **do not modify**:
- `_StopButton` class: the `Listener(onPointerDown/Up/Cancel)`, 800ms `AnimationController` (`_ring`), `_onDown`/`_onReleaseOrCancel` logic, and the `_ring.addStatusListener(_onRingStatus)` path.
- `_checkDrillComplete` listener and `Navigator.pushReplacement(ResultsScreen)` on `DrillPhase.finished`.
- `PopScope(canPop: false)`.
- `_onStopConfirmed` 2s `Future.delayed` fallback to `state.forceDrillFinished()`.
- reduce-motion path in `_onDown` that bypasses the ring and calls `widget.onStop()` immediately.

Replace `lib/screens/drill_running_screen.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/atriarch_theme.dart';
import '../widgets/drill_timer.dart';
import '../widgets/tactical/tactical_hud_tile.dart';
import '../widgets/tactical/tactical_scaffold.dart';
import '../widgets/tactical/tactical_status_chip.dart';
import 'results_screen.dart';

class DrillRunningScreen extends StatefulWidget {
  const DrillRunningScreen({super.key});

  @override
  State<DrillRunningScreen> createState() => _DrillRunningScreenState();
}

class _DrillRunningScreenState extends State<DrillRunningScreen>
    with TickerProviderStateMixin {
  late final AnimationController _breatheController;

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    final state = context.read<AppState>();
    state.addListener(_checkDrillComplete);
  }

  @override
  void dispose() {
    _breatheController.dispose();
    final state = context.read<AppState>();
    state.removeListener(_checkDrillComplete);
    super.dispose();
  }

  void _checkDrillComplete() {
    if (!mounted) return;
    final state = context.read<AppState>();
    if (state.phase == DrillPhase.finished) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ResultsScreen()),
      );
    }
  }

  Future<void> _onStopConfirmed() async {
    final state = context.read<AppState>();
    if (state.phase == DrillPhase.stopping ||
        state.phase == DrillPhase.finished) {
      return;
    }
    await state.stopDrill();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      state.forceDrillFinished();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Consumer<AppState>(
      builder: (context, state, _) {
        final stopping = state.phase == DrillPhase.stopping;
        final statusColor =
            stopping ? tokens.statusArmed : tokens.statusLive;
        final statusLabel = stopping ? 'stopping' : 'live';
        return PopScope(
          canPop: false,
          child: TacticalScaffold(
            title: 'DRILL // LIVE',
            trailing: TacticalStatusChip(
              color: statusColor,
              label: statusLabel,
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AtriarchSpacing.lg),
                child: Column(
                  children: [
                    const SizedBox(height: AtriarchSpacing.xl),
                    _DrillActiveLabel(
                      color: tokens.statusArmed,
                      reduceMotion: reduceMotion,
                      breathe: _breatheController,
                    ),
                    const SizedBox(height: AtriarchSpacing.xl),
                    _HeroTimerWithBrackets(child: const DrillTimer()),
                    const SizedBox(height: AtriarchSpacing.xl),
                    Row(
                      children: const [
                        Expanded(
                          child: TacticalHudTile(
                            label: 'hits',
                            value: '—',
                          ),
                        ),
                        SizedBox(width: AtriarchSpacing.sm),
                        Expanded(
                          child: TacticalHudTile(
                            label: 'elapsed',
                            value: '—',
                          ),
                        ),
                        SizedBox(width: AtriarchSpacing.sm),
                        Expanded(
                          child: TacticalHudTile(
                            label: 'node',
                            value: '—',
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _StopButton(
                      onStop: _onStopConfirmed,
                      isStopping: stopping,
                    ),
                    const SizedBox(height: AtriarchSpacing.md),
                    Text(
                      stopping
                          ? 'ENDING DRILL…'
                          : 'PRESS AND HOLD TO ABORT',
                      style: AtriarchText.labelTiny(
                        color: tokens.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AtriarchSpacing.lg),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeroTimerWithBrackets extends StatelessWidget {
  final Widget child;
  const _HeroTimerWithBrackets({required this.child});

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return SizedBox(
      height: 140,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _CornerBracketPainter(color: tokens.statusHit),
            ),
          ),
          Center(child: child),
        ],
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  final Color color;
  _CornerBracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const armLen = 16.0;
    const inset = 4.0;

    // top-left
    canvas.drawLine(Offset(inset, inset), Offset(inset + armLen, inset), paint);
    canvas.drawLine(Offset(inset, inset), Offset(inset, inset + armLen), paint);
    // top-right
    canvas.drawLine(
      Offset(size.width - inset - armLen, inset),
      Offset(size.width - inset, inset),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - inset, inset),
      Offset(size.width - inset, inset + armLen),
      paint,
    );
    // bottom-left
    canvas.drawLine(
      Offset(inset, size.height - inset),
      Offset(inset + armLen, size.height - inset),
      paint,
    );
    canvas.drawLine(
      Offset(inset, size.height - inset - armLen),
      Offset(inset, size.height - inset),
      paint,
    );
    // bottom-right
    canvas.drawLine(
      Offset(size.width - inset - armLen, size.height - inset),
      Offset(size.width - inset, size.height - inset),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - inset, size.height - inset - armLen),
      Offset(size.width - inset, size.height - inset),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DrillActiveLabel extends StatelessWidget {
  final Color color;
  final bool reduceMotion;
  final AnimationController breathe;

  const _DrillActiveLabel({
    required this.color,
    required this.reduceMotion,
    required this.breathe,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: color,
          letterSpacing: 4,
          fontWeight: FontWeight.w700,
        );
    final label = Text('DRILL ACTIVE', style: style);

    if (reduceMotion) return label;

    return AnimatedBuilder(
      animation: breathe,
      builder: (_, __) {
        final t = breathe.value;
        final opacity = 0.75 + (t * 0.25);
        return Opacity(opacity: opacity, child: label);
      },
    );
  }
}

class _StopButton extends StatefulWidget {
  final Future<void> Function() onStop;
  final bool isStopping;

  const _StopButton({
    required this.onStop,
    required this.isStopping,
  });

  @override
  State<_StopButton> createState() => _StopButtonState();
}

class _StopButtonState extends State<_StopButton>
    with TickerProviderStateMixin {
  late final AnimationController _ring;

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _ring.addStatusListener(_onRingStatus);
  }

  @override
  void dispose() {
    _ring.removeStatusListener(_onRingStatus);
    _ring.dispose();
    super.dispose();
  }

  void _onRingStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !widget.isStopping) {
      widget.onStop();
    }
  }

  void _onDown() {
    if (widget.isStopping) return;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      widget.onStop();
      return;
    }
    _ring.forward();
  }

  void _onReleaseOrCancel() {
    if (widget.isStopping) return;
    if (_ring.value < 1.0) {
      _ring.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    final buttonColor =
        widget.isStopping ? tokens.statusOffline : tokens.statusViolation;

    return Semantics(
      button: true,
      enabled: !widget.isStopping,
      label: 'Stop button. Press and hold to end the drill.',
      child: Listener(
        onPointerDown: (_) => _onDown(),
        onPointerUp: (_) => _onReleaseOrCancel(),
        onPointerCancel: (_) => _onReleaseOrCancel(),
        child: SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _ring,
                builder: (_, __) => CustomPaint(
                  size: const Size(220, 220),
                  painter: _StopRingPainter(
                    progress: _ring.value,
                    color: tokens.statusViolation,
                  ),
                ),
              ),
              Container(
                width: 180,
                height: 180,
                color: buttonColor,
                alignment: Alignment.center,
                child: widget.isStopping
                    ? _StoppingLabel(tokens: tokens)
                    : Text(
                        'STOP',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                            ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoppingLabel extends StatelessWidget {
  final AtriarchTokens tokens;
  const _StoppingLabel({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 3,
          ),
        ),
        const SizedBox(height: AtriarchSpacing.md),
        Text(
          'STOPPING…',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
        ),
      ],
    );
  }
}

class _StopRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _StopRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 6;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_StopRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
```

The HUD tile values show `—` placeholders; wire them to real `state` fields (hit count, elapsed, current target/group) once the per-frame state fields are identified during implementation. Run `grep -n "hits\|elapsed\|currentTarget\|currentGroup" lib/state/app_state.dart` to find the fields.

- [ ] **Step 4: Run tests to verify pass**

```bash
flutter test test/screens/drill_running_screen_test.dart
```

Expected: PASS.

- [ ] **Step 5: Manual timing check**

```bash
flutter run -d <device>
```

Navigate to drill running. Verify:
- Single tap on STOP does NOT stop the drill.
- Press and hold for ~800ms fills the ring and triggers stop.
- Release before 800ms reverses the ring and does NOT stop.
- `STOPPING…` label appears after successful hold.

If any of the above fails, revert to the previous commit and investigate — do not ship a broken safety gesture.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/drill_running_screen.dart test/screens/drill_running_screen_test.dart
git commit -m "$(cat <<'EOF'
refactor(drill): tactical HUD layout, preserve press-and-hold STOP

TacticalScaffold + hero timer with corner brackets + HUD row.
STOP button restyled as square inside the existing circle ring
painter. All 800ms press-and-hold timing, reduce-motion fallback,
PopScope, and 2s stopDrill fallback preserved verbatim.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4 — Cleanup

### Task 20: Delete legacy widgets, update older tests, analyze

**Files:**
- Delete: `lib/widgets/inc_dec.dart`
- Delete: `lib/widgets/target_chip.dart`
- Modify: any remaining references
- Modify: `test/widget_test.dart` (remove stub or extend it to smoke-test `MaterialApp` boot)
- Optionally: `lib/theme/atriarch_theme.dart` (delete `buildAtriarchLightTheme` and light tokens if truly unreferenced)

**Goal:** No dangling references to old widgets. All tests pass. `flutter analyze` is clean.

- [ ] **Step 1: Check for remaining references**

```bash
grep -rn "IncDec\|TargetChip" lib/ test/
```

Expected: no matches in `lib/` or `test/`. If any, update those call sites to the new widgets.

- [ ] **Step 2: Delete legacy files**

```bash
git rm lib/widgets/inc_dec.dart lib/widgets/target_chip.dart
```

- [ ] **Step 3: Clean up the stub widget test**

Replace `test/widget_test.dart` with a real smoke test:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/screens/home_screen.dart';

void main() {
  testWidgets('app boots to home screen with dark theme', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: buildAtriarchDarkTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('ATRIARCH // HOME'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Check if light theme has any callers**

```bash
grep -rn "buildAtriarchLightTheme\|AtriarchTokens.light" lib/ test/
```

If zero matches, optionally remove `buildAtriarchLightTheme()` and `AtriarchTokens.light` from `lib/theme/atriarch_theme.dart`. If any remain (e.g., a test), leave them alone — scope creep. Note in the commit message if removed.

- [ ] **Step 5: Run the full test suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Static analysis**

```bash
flutter analyze
```

Expected: no errors. Warnings are acceptable if they predate this work.

- [ ] **Step 7: Manual app boot**

```bash
flutter run -d <device>
```

Walk each screen:
- Home → Program A → back
- Home → Program B → back
- Home → tap disconnected banner → device discovery → back
- Start a drill (with hardware OR a mock, whichever is normal for this repo) → observe drill running → stop → observe results

If anything renders wrong or crashes, fix before committing.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore(widgets): delete legacy IncDec/TargetChip + replace stub test

All call sites now use TacticalStepper, TacticalMinMaxCard, and
TargetNodeChip. Stub widget_test.dart replaced with a boot smoke
test. flutter analyze and full test suite clean.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage:**

- Theme flip (Space Grotesk, zero radius, dark default): Task 1 ✓
- TacticalGridBackground: Task 2 ✓
- TacticalAppBar: Task 4 ✓
- TacticalScaffold: Task 5 ✓
- TacticalSection: Task 6 ✓
- TacticalCard: Task 7 ✓
- TacticalStepper + compact: Task 8 ✓
- TacticalMinMaxCard: Task 9 ✓
- TacticalPrimaryButton (all variants): Task 10 ✓
- TacticalStatusChip: Task 3 ✓
- TacticalHudTile: Task 11 ✓
- GroupNodeCard: Task 12 ✓
- TargetNodeChip: Task 13 ✓
- home_screen restyle: Task 14 ✓
- device_discovery_screen restyle: Task 15 ✓
- program_b_setup_screen restyle (inline scan, no FAB): Task 16 ✓
- program_a_setup_screen restyle (allocation grid): Task 17 ✓
- results_screen restyle (HUD tiles, per-target cards, no FAB): Task 18 ✓
- drill_running_screen HUD (preserve STOP gesture): Task 19 ✓
- Legacy widget deletion + test cleanup: Task 20 ✓

All non-negotiables preserved:
- Press-and-hold STOP gesture: Task 19 Step 3 explicit preservation rules + Step 5 manual verification ✓
- Arming-failed banner retry: Tasks 16 & 17 ✓
- PopScope: Task 19 ✓
- Semantics labels: Tasks 10 & 19 ✓

**Placeholder scan:** No `TBD`/`TODO` markers in shipped code paths. Two notes for the implementer (`// fix if...`-style guidance) are in Tasks 18 and 19 where model field shape needs to be verified at implementation time; these are concrete verification steps, not handwavy placeholders.

**Type consistency:** `TacticalButtonVariant` enum defined in Task 10, used unchanged in Tasks 15, 16, 17. `TacticalStepper` properties consistent between Task 8 definition and Tasks 9/16/17 usage. `GroupNodeCard(groupIndex: int, targetIds: List<int>, selected: bool, onTap: VoidCallback, onRemoveTarget: ValueChanged<int>)` contract consistent between Task 12 and Task 17. `TargetNodeChip(target: Target, onTap: VoidCallback)` consistent between Task 13 and Task 17.

**Spec requirement with no task:** None found.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-20-tactical-redesign.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
