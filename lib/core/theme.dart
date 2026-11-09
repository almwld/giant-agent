import 'package:flutter/material.dart';

/// Shared Sehatak-inspired brand palette for Giant Agent.
/// Layouts and interaction patterns remain unchanged; only visual tokens
/// are centralized here so every screen can inherit the same identity.
class AppTheme {
  static const Color primary = Color(0xFF0A8F83);
  static const Color primaryColor = primary;
  static const Color primaryLight = Color(0xFF34A99F);
  static const Color primaryDark = Color(0xFF08776E);
  static const Color secondary = Color(0xFF1A73E8);
  static const Color accent = secondary;

  static const Color background = Color(0xFFF4F6F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF263238);
  static const Color textLight = Color(0xFF607078);
  static const Color error = Color(0xFFDC4545);
  static const Color success = Color(0xFF0A8F83);
  static const Color warning = Color(0xFFF59E0B);

  static const Color darkBackground = Color(0xFF263238);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkText = Color(0xFFFFFFFF);
  static const Color darkTextLight = Color(0xFFB0BEC5);
  static const Color glassDark = darkSurface;

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDark],
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [darkBackground, darkSurface],
  );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primary,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFDDF2EF),
      onPrimaryContainer: Color(0xFF075B54),
      secondary: secondary,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: text,
      error: error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: text,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: text),
      titleTextStyle: TextStyle(
        color: text,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardTheme(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFFF4F6F7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      hintStyle: const TextStyle(color: textLight),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: background,
      selectedColor: primary,
      labelStyle: const TextStyle(color: text),
      secondaryLabelStyle: const TextStyle(color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: primary,
    scaffoldBackgroundColor: darkBackground,
    colorScheme: const ColorScheme.dark(
      primary: primaryLight,
      onPrimary: Color(0xFF062F2B),
      primaryContainer: Color(0xFF164B46),
      onPrimaryContainer: Color(0xFFDDF2EF),
      secondary: Color(0xFF6AA8F5),
      onSecondary: Color(0xFF102B4D),
      surface: darkSurface,
      onSurface: darkText,
      error: Color(0xFFFF7777),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: darkSurface,
      foregroundColor: darkText,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: darkText),
      titleTextStyle: TextStyle(
        color: darkText,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardTheme(
      color: darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primaryLight, width: 1.5),
      ),
      hintStyle: const TextStyle(color: darkTextLight),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: darkSurface,
      selectedColor: primary,
      labelStyle: const TextStyle(color: darkText),
      secondaryLabelStyle: const TextStyle(color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
