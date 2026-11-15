import 'package:flutter/material.dart';

/// Calm light theme, Jost everywhere. Rounded rectangles, no pills.
class HqColors {
  static const background = Color(0xFFF6F6F4);
  static const surface = Colors.white;
  static const sidebar = Color(0xFFEEEEEB);
  static const ink = Color(0xFF1E1F22);
  static const muted = Color(0xFF6E7076);
  static const line = Color(0xFFE2E2DE);
  static const accent = Color(0xFF0089A8); // Gemstok cyan, darkened for a light background
  static const good = Color(0xFF1F9D55);
  static const bad = Color(0xFFD14343);
  static const warn = Color(0xFFC98A00);
  static const claude = Color(0xFFC15F3C); // Ask Claude — warm clay, apart from the business screens
  static const claudeTint = Color(0xFFF6E9E3);
}

/// Jost is a variable font: pick the weight with a font variation.
TextStyle jost(double size, {double weight = 400, Color color = HqColors.ink}) => TextStyle(
      fontFamily: 'Jost',
      fontSize: size,
      color: color,
      fontVariations: [FontVariation('wght', weight)],
    );

ThemeData hqTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Jost',
    scaffoldBackgroundColor: HqColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: HqColors.accent,
      brightness: Brightness.light,
      surface: HqColors.surface,
    ),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: shape)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: shape)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: shape)),
    dividerColor: HqColors.line,
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      isDense: true,
    ),
  );
}
