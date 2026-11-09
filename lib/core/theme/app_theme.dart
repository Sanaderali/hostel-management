import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF3F4DA8);
  static const electricity = Color(0xFF6FB195);
  static const water = Color(0xFF6E78CC);
  static const gas = Color(0xFFA67FC4);
  static const studentsTint = Color(0xFFDDF3FB);
  static const billsTint = Color(0xFFFCE4EC);
}

class AppTheme {
  static ThemeData _build(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: b);
    final dark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF111318) : Colors.white,
      appBarTheme: const AppBarTheme(centerTitle: true, scrolledUnderElevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF1C1F26) : const Color(0xFFF6F7FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);
}
