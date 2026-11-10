import 'package:flutter/material.dart';

/// AgentsOS application design system using Sehatak's approved brand palette.
/// Keep product semantics and status colors distinct from decorative branding.
class AppTheme {
  static const Color primary = Color(0xFF0A8F83);
  static const Color primaryColor = primary;
  static const Color primaryLight = Color(0xFF34A99F);
  static const Color primaryDark = Color(0xFF08776E);
  static const Color secondary = Color(0xFF1A73E8);
  static const Color accent = secondary;

  static const Color background = Color(0xFFF4F6F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFEEF3F4);
  static const Color text = Color(0xFF263238);
  static const Color textLight = Color(0xFF607078);
  static const Color error = Color(0xFFDC4545);
  static const Color success = Color(0xFF0A8F83);
  static const Color warning = Color(0xFFF59E0B);

  static const Color darkBackground = Color(0xFF111C2B);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkElevated = Color(0xFF263548);
  static const Color darkText = Color(0xFFF7FAFC);
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

  static const _radius = 18.0;

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primary,
    scaffoldBackgroundColor: background,
    canvasColor: background,
    visualDensity: VisualDensity.standard,
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
      backgroundColor: background,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: text,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -.35,
      ),
      iconTheme: IconThemeData(color: text),
    ),
    cardTheme: CardTheme(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
        side: const BorderSide(color: Color(0xFFE7EDEF)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(46, 46),
        side: const BorderSide(color: Color(0xFFB8D9D5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDCE5E7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDCE5E7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFFEAF4F2),
      selectedColor: const Color(0xFFDDF2EF),
      secondarySelectedColor: const Color(0xFFDCEAFF),
      labelStyle: const TextStyle(color: text, fontWeight: FontWeight.w600),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE7EDEF),
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF173C3A),
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: primary,
    scaffoldBackgroundColor: darkBackground,
    canvasColor: darkBackground,
    visualDensity: VisualDensity.standard,
    colorScheme: const ColorScheme.dark(
      primary: primaryLight,
      onPrimary: Color(0xFF062F2B),
      primaryContainer: Color(0xFF164B46),
      onPrimaryContainer: Color(0xFFDDF2EF),
      secondary: secondary,
      onSecondary: Colors.white,
      surface: darkSurface,
      onSurface: darkText,
      error: Color(0xFFFF7777),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: darkBackground,
      foregroundColor: darkText,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: darkText,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -.35,
      ),
      iconTheme: IconThemeData(color: darkText),
    ),
    cardTheme: CardTheme(
      color: darkSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
        side: const BorderSide(color: Color(0xFF344456)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryLight,
        minimumSize: const Size(46, 46),
        side: const BorderSide(color: Color(0xFF42645F)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkElevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF3B4C5E)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF3B4C5E)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primaryLight, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFF263D4A),
      selectedColor: const Color(0xFF164B46),
      secondarySelectedColor: const Color(0xFF203E64),
      labelStyle: const TextStyle(color: darkText, fontWeight: FontWeight.w600),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF344456),
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF173C3A),
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
