import 'package:flutter/material.dart';

class DesignTokens {
  // Colors
  static const Color primary = Color(0xFFD4AF37); // gold
  static const Color background = Colors.white;
  static const Color surface = Colors.white;
  static const Color ink = Color(0xFF0B0B0B);
  static const Color muted = Color(0xFF6B7280);

  // Radii
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 18.0;

  // Spacing
  static const double spacingXS = 6.0;
  static const double spacingSm = 12.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;

  // Elevation shadows
  static const List<BoxShadow> elevatedShadow = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 6)),
  ];

  // Theme helper
  static ThemeData themeData({String fontFamily = 'Cairo'}) {
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
          seedColor: primary, brightness: Brightness.light),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: ink,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMedium)),
        ),
      ),
      textTheme: const TextTheme(
        titleLarge:
            TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: ink),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF1F2937)),
      ),
    );
  }
}
