// Atriarch design tokens + light theme (Gate 1).
// DARK theme + ambient-light auto-toggle land in Gate 2.
// See DESIGN.md at repo root for the full spec.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

@immutable
class AtriarchTokens extends ThemeExtension<AtriarchTokens> {
  final Color bgBase;
  final Color bgElevated;
  final Color bgCard;
  final Color border;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color statusArmed;
  final Color statusLive;
  final Color statusHit;
  final Color statusViolation;
  final Color statusLate;
  final Color statusOffline;
  final Color statusUnreachable;

  final Color groupMagenta;
  final Color groupCyan;
  final Color groupYellow;
  final Color groupPurple;
  final Color groupLime;

  const AtriarchTokens({
    required this.bgBase,
    required this.bgElevated,
    required this.bgCard,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.statusArmed,
    required this.statusLive,
    required this.statusHit,
    required this.statusViolation,
    required this.statusLate,
    required this.statusOffline,
    required this.statusUnreachable,
    required this.groupMagenta,
    required this.groupCyan,
    required this.groupYellow,
    required this.groupPurple,
    required this.groupLime,
  });

  Color groupColor(int groupIndex) {
    switch (groupIndex) {
      case 1:
        return groupMagenta;
      case 2:
        return groupCyan;
      case 3:
        return groupYellow;
      case 4:
        return groupPurple;
      case 5:
        return groupLime;
      default:
        return statusOffline;
    }
  }

  static const AtriarchTokens light = AtriarchTokens(
    bgBase: Color(0xFFFFFFFF),
    bgElevated: Color(0xFFF2F5FA),
    bgCard: Color(0xFFE8EDF5),
    border: Color(0xFFC3CBD9),
    textPrimary: Color(0xFF0A0D12),
    textSecondary: Color(0xFF3A4355),
    textTertiary: Color(0xFF6A7388),
    statusArmed: Color(0xFFB76E00),
    statusLive: Color(0xFF0E7A3E),
    statusHit: Color(0xFF1E4FC7),
    statusViolation: Color(0xFFB3001F),
    statusLate: Color(0xFFB36F00),
    statusOffline: Color(0xFF6A7388),
    statusUnreachable: Color(0xFFB3001F),
    groupMagenta: Color(0xFFC71585),
    groupCyan: Color(0xFF0891B2),
    groupYellow: Color(0xFFB45309),
    groupPurple: Color(0xFF6D28D9),
    groupLime: Color(0xFF4D7C0F),
  );

  static const AtriarchTokens dark = AtriarchTokens(
    bgBase: Color(0xFF0A0D12),
    bgElevated: Color(0xFF141820),
    bgCard: Color(0xFF1A1F2A),
    border: Color(0xFF2A3140),
    textPrimary: Color(0xFFE8EDF5),
    textSecondary: Color(0xFF8892A8),
    textTertiary: Color(0xFF4A5365),
    statusArmed: Color(0xFFF5A623),
    statusLive: Color(0xFF39D98A),
    statusHit: Color(0xFF5B9BFF),
    statusViolation: Color(0xFFFF3B4D),
    statusLate: Color(0xFFFFB547),
    statusOffline: Color(0xFF4A5365),
    statusUnreachable: Color(0xFFFF3B4D),
    groupMagenta: Color(0xFFFF3DB0),
    groupCyan: Color(0xFF22D3EE),
    groupYellow: Color(0xFFFACC15),
    groupPurple: Color(0xFFA78BFA),
    groupLime: Color(0xFF84CC16),
  );

  @override
  AtriarchTokens copyWith({
    Color? bgBase,
    Color? bgElevated,
    Color? bgCard,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? statusArmed,
    Color? statusLive,
    Color? statusHit,
    Color? statusViolation,
    Color? statusLate,
    Color? statusOffline,
    Color? statusUnreachable,
    Color? groupMagenta,
    Color? groupCyan,
    Color? groupYellow,
    Color? groupPurple,
    Color? groupLime,
  }) {
    return AtriarchTokens(
      bgBase: bgBase ?? this.bgBase,
      bgElevated: bgElevated ?? this.bgElevated,
      bgCard: bgCard ?? this.bgCard,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      statusArmed: statusArmed ?? this.statusArmed,
      statusLive: statusLive ?? this.statusLive,
      statusHit: statusHit ?? this.statusHit,
      statusViolation: statusViolation ?? this.statusViolation,
      statusLate: statusLate ?? this.statusLate,
      statusOffline: statusOffline ?? this.statusOffline,
      statusUnreachable: statusUnreachable ?? this.statusUnreachable,
      groupMagenta: groupMagenta ?? this.groupMagenta,
      groupCyan: groupCyan ?? this.groupCyan,
      groupYellow: groupYellow ?? this.groupYellow,
      groupPurple: groupPurple ?? this.groupPurple,
      groupLime: groupLime ?? this.groupLime,
    );
  }

  @override
  AtriarchTokens lerp(ThemeExtension<AtriarchTokens>? other, double t) {
    if (other is! AtriarchTokens) return this;
    return AtriarchTokens(
      bgBase: Color.lerp(bgBase, other.bgBase, t)!,
      bgElevated: Color.lerp(bgElevated, other.bgElevated, t)!,
      bgCard: Color.lerp(bgCard, other.bgCard, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      statusArmed: Color.lerp(statusArmed, other.statusArmed, t)!,
      statusLive: Color.lerp(statusLive, other.statusLive, t)!,
      statusHit: Color.lerp(statusHit, other.statusHit, t)!,
      statusViolation: Color.lerp(statusViolation, other.statusViolation, t)!,
      statusLate: Color.lerp(statusLate, other.statusLate, t)!,
      statusOffline: Color.lerp(statusOffline, other.statusOffline, t)!,
      statusUnreachable:
          Color.lerp(statusUnreachable, other.statusUnreachable, t)!,
      groupMagenta: Color.lerp(groupMagenta, other.groupMagenta, t)!,
      groupCyan: Color.lerp(groupCyan, other.groupCyan, t)!,
      groupYellow: Color.lerp(groupYellow, other.groupYellow, t)!,
      groupPurple: Color.lerp(groupPurple, other.groupPurple, t)!,
      groupLime: Color.lerp(groupLime, other.groupLime, t)!,
    );
  }
}

class AtriarchSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double hero = 64;

  const AtriarchSpacing._();
}

class AtriarchRadius {
  static const double sm = 0;
  static const double md = 0;
  static const double lg = 0;
  static const double full = 9999;

  const AtriarchRadius._();
}

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

extension AtriarchThemeContext on BuildContext {
  AtriarchTokens get atriarch =>
      Theme.of(this).extension<AtriarchTokens>() ?? AtriarchTokens.light;
}

ThemeData buildAtriarchLightTheme() {
  const tokens = AtriarchTokens.light;

  final sansTheme = GoogleFonts.interTightTextTheme();
  final mono = GoogleFonts.jetBrainsMono;

  final textTheme = sansTheme.copyWith(
    displayLarge: mono(
      fontSize: 96,
      fontWeight: FontWeight.w300,
      color: tokens.textPrimary,
    ),
    displayMedium: mono(
      fontSize: 48,
      fontWeight: FontWeight.w300,
      color: tokens.textPrimary,
    ),
    displaySmall: mono(
      fontSize: 28,
      fontWeight: FontWeight.w500,
      color: tokens.textPrimary,
    ),
    headlineMedium: GoogleFonts.interTight(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
    ),
    titleLarge: GoogleFonts.interTight(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
    ),
    titleMedium: GoogleFonts.interTight(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: tokens.textPrimary,
    ),
    bodyLarge: GoogleFonts.interTight(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: tokens.textPrimary,
    ),
    bodyMedium: GoogleFonts.interTight(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: tokens.textPrimary,
    ),
    bodySmall: GoogleFonts.interTight(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: tokens.textSecondary,
    ),
    labelLarge: GoogleFonts.interTight(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
    ),
    labelSmall: GoogleFonts.interTight(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.8,
      color: tokens.textTertiary,
    ),
  );

  final colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: tokens.textPrimary,
    onPrimary: tokens.bgBase,
    secondary: tokens.statusArmed,
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
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: tokens.bgBase,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.bgBase,
      foregroundColor: tokens.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.interTight(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: tokens.textPrimary,
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AtriarchRadius.md),
        side: BorderSide(color: tokens.border),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: tokens.textPrimary,
        foregroundColor: tokens.bgBase,
        minimumSize: const Size(44, 56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AtriarchRadius.md),
        ),
        textStyle: GoogleFonts.interTight(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        side: BorderSide(color: tokens.border),
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AtriarchRadius.md),
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
      labelStyle: GoogleFonts.interTight(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: tokens.textPrimary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AtriarchRadius.sm),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.bgCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AtriarchRadius.sm),
        borderSide: BorderSide(color: tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AtriarchRadius.sm),
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AtriarchRadius.sm),
        borderSide: BorderSide(color: tokens.textPrimary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AtriarchSpacing.lg,
        vertical: AtriarchSpacing.md,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.textPrimary,
      contentTextStyle: GoogleFonts.interTight(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: tokens.bgBase,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AtriarchRadius.md),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    extensions: const [tokens],
  );
}

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
