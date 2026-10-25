import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Shared school operations palette: warm neutral surfaces and berry accents.
class LgColors {
  static const background = Color(0xFFF7F7FA);
  static const surface = Color(0xFFFFFFFF);
  static const accent = Color(0xFF9D2453);
  static const accentSoft = Color(0xFFF8EAF0);
  static const ink = Color(0xFF282638);
  static const muted = Color(0xFF646174);
  static const line = Color(0xFFE5E3EC);
  static const ok = Color(0xFF1B7A32);
  static const okBg = Color(0xFFE5F6EA);
  static const warn = Color(0xFFC2410C);
  static const warnBg = Color(0xFFFFF1E6);
  static const danger = Color(0xFFB42318);
  static const dangerBg = Color(0xFFFDECEA);
  static const infoBg = Color(0xFFE8F1FB);
  static const info = Color(0xFF0D47A1);

  static const avatarBackgrounds = [
    Color(0xFFF8D7E3),
    Color(0xFFD9EFE0),
    Color(0xFFFFE4C8),
    Color(0xFFD9E6F7),
    Color(0xFFE7DDF5),
  ];
  static const avatarForegrounds = [
    Color(0xFF8E1248),
    Color(0xFF1B5E20),
    Color(0xFF8A3B00),
    Color(0xFF0D47A1),
    Color(0xFF4A148C),
  ];
}

ThemeData buildTheme() {
  const radius = 18.0;
  final scheme = ColorScheme.fromSeed(
    seedColor: LgColors.accent,
    primary: LgColors.accent,
    onPrimary: Colors.white,
    surface: LgColors.surface,
    onSurface: LgColors.ink,
  );
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: scheme,
    scaffoldBackgroundColor: LgColors.background,
  );
  final text = base.textTheme.apply(
    bodyColor: LgColors.ink,
    displayColor: LgColors.ink,
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
  );
  return base.copyWith(
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.2,
        color: LgColors.ink,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: LgColors.ink,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: LgColors.ink,
      ),
      bodyLarge: text.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.4,
        color: LgColors.ink,
      ),
      bodyMedium: text.bodyMedium?.copyWith(
        fontSize: 15,
        height: 1.4,
        color: LgColors.ink,
      ),
      labelLarge: text.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: LgColors.background,
      foregroundColor: LgColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        color: LgColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: LgColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: LgColors.line),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: LgColors.accent,
      unselectedLabelColor: LgColors.muted,
      indicatorColor: LgColors.accent,
      dividerColor: LgColors.line,
      labelStyle: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: LgColors.muted,
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    ),
    dividerTheme: const DividerThemeData(
      color: LgColors.line,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: LgColors.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFE7D5DE),
        disabledForegroundColor: LgColors.muted,
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: LgColors.ink,
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        side: const BorderSide(color: LgColors.line),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: LgColors.accent,
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LgColors.surface,
      hintStyle: const TextStyle(fontFamily: 'Inter', color: LgColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: LgColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: LgColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: LgColors.accent, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: LgColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: LgColors.accentSoft,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          color: selected ? LgColors.accent : LgColors.muted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? LgColors.accent : LgColors.muted,
          size: 24,
        );
      }),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: LgColors.ink,
      contentTextStyle: TextStyle(
        fontFamily: 'Inter',
        color: Colors.white,
        fontSize: 15,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: LgColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        fontFamily: 'Inter',
        color: LgColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: 'Inter',
        color: LgColors.ink,
        fontSize: 16,
        height: 1.4,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: LgColors.surface,
      selectedColor: LgColors.accentSoft,
      disabledColor: const Color(0xFFF3EEE8),
      labelStyle: const TextStyle(
        fontFamily: 'Inter',
        color: LgColors.ink,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: 'Inter',
        color: LgColors.accent,
        fontWeight: FontWeight.w700,
      ),
      side: const BorderSide(color: LgColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      showCheckmark: false,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: LgColors.accent,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
