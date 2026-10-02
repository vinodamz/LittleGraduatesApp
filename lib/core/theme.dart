import 'package:flutter/material.dart';

/// Colours from the MTT web app (warm cream background, school pink accent).
class LgColors {
  static const background = Color(0xFFFFF8F0);
  static const accent = Color(0xFFC2185B);
  static const ink = Color(0xFF2B2B2B);
  static const muted = Color(0xFF8A7F72);
  static const line = Color(0xFFEADFCF);
  static const ok = Color(0xFF2E7D32);
  static const warn = Color(0xFFE65100);
  static const warnBg = Color(0xFFFFF4E1);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: LgColors.accent, surface: Colors.white);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: LgColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: LgColors.background,
      foregroundColor: LgColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: LgColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48), backgroundColor: LgColors.accent),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
    ),
  );
}
