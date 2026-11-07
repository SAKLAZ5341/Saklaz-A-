import 'package:flutter/material.dart';

/// SAKLAZ marka renkleri: gece mavisi zemin, camgöbeği -> mor enerji gradyanı.
abstract final class SaklazColors {
  static const background = Color(0xFF060912);
  static const surface = Color(0xFF0E1424);
  static const surfaceHigh = Color(0xFF161E33);
  static const outline = Color(0xFF26304A);
  static const cyan = Color(0xFF3FE0F5);
  static const violet = Color(0xFF8B5CF6);
  static const magenta = Color(0xFFE15BF0);
  static const listening = Color(0xFF34E39A);
  static const speaking = Color(0xFF8B9CFF);
  static const warning = Color(0xFFFFB547);
  static const danger = Color(0xFFFF5C7A);
  static const textPrimary = Color(0xFFEAF0FF);
  static const textSecondary = Color(0xFF94A0BD);

  static const brandGradient = LinearGradient(
    colors: [cyan, violet, magenta],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildSaklazTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: SaklazColors.violet,
    brightness: Brightness.dark,
  ).copyWith(
    primary: SaklazColors.cyan,
    secondary: SaklazColors.violet,
    tertiary: SaklazColors.magenta,
    surface: SaklazColors.surface,
    surfaceContainerHighest: SaklazColors.surfaceHigh,
    outline: SaklazColors.outline,
    error: SaklazColors.danger,
    onSurface: SaklazColors.textPrimary,
    onSurfaceVariant: SaklazColors.textSecondary,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: SaklazColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: SaklazColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: SaklazColors.outline),
      ),
    ),
    listTileTheme: const ListTileThemeData(iconColor: SaklazColors.textSecondary),
    textTheme: base.textTheme.apply(
      bodyColor: SaklazColors.textPrimary,
      displayColor: SaklazColors.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SaklazColors.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
  );
}
