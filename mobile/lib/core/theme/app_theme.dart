import 'package:flutter/material.dart';

/// Paleta AlertaBGA, compartida con el dashboard web.
abstract final class BrandColors {
  static const navy950 = Color(0xFF061428);
  static const navy900 = Color(0xFF0B1F3A);
  static const navy800 = Color(0xFF13305A);
  static const cyan = Color(0xFF06B6D4);
  static const amber = Color(0xFFF59E0B);
  static const slate50 = Color(0xFFF6F8FB);
  static const slate500 = Color(0xFF64748B);
  static const danger = Color(0xFFDC2626);
  static const success = Color(0xFF059669);
}

abstract final class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.navy900,
      primary: BrandColors.navy900,
      secondary: BrandColors.cyan,
      tertiary: BrandColors.amber,
      error: BrandColors.danger,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: BrandColors.slate50,
      appBarTheme: const AppBarTheme(
        backgroundColor: BrandColors.navy900,
        foregroundColor: Colors.white,
        centerTitle: false,
      ),
      // Botones grandes: el flujo de reporte debe ser fácil de usar bajo estrés.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFDDE4EE)),
        ),
      ),
    );
  }
}
