import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      splashFactory: InkRipple.splashFactory,
      splashColor: const Color(0xFFD4AF37).withValues(alpha: 0.24),
      highlightColor: const Color(0xFFD4AF37).withValues(alpha: 0.14),
      hoverColor: const Color(0xFFD4AF37).withValues(alpha: 0.10),
      focusColor: const Color(0xFFD4AF37).withValues(alpha: 0.16),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFD4AF37),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Color(0xFF0B0B0B),
        foregroundColor: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: Color(0xFFD4AF37),
        unselectedItemColor: Color(0xFF6B7280),
        backgroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD4AF37),
          foregroundColor: Colors.black,
          overlayColor: const Color(0xFF7A5E00),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          overlayColor: const Color(0xFFD4AF37).withValues(alpha: 0.18),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          overlayColor: const Color(0xFFD4AF37).withValues(alpha: 0.18),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          overlayColor: const Color(0xFFD4AF37).withValues(alpha: 0.20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.3),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFFE9D5FF),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2937),
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        titleLarge: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF0B0B0B),
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          color: Color(0xFF1F2937),
        ),
      ),
      primaryTextTheme: base.primaryTextTheme.copyWith(
        bodyMedium: const TextStyle(
          color: Color(0xFF1F2937),
        ),
      ),
    );
  }
}
