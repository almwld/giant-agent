import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  static const String _themeKey = 'theme_mode';
  static const String _colorKey = 'accent_color';
  
  static Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_themeKey) ?? 0;
    return ThemeMode.values[index];
  }
  
  static Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
  }
  
  static Future<Color> getAccentColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt(_colorKey) ?? 0xFF0A8F83;
    return Color(colorValue);
  }
  
  static Future<void> setAccentColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_colorKey, color.value);
  }
  
  static List<Color> getAvailableColors() => [
    const Color(0xFF0A8F83), // تركواز صحّتك
    const Color(0xFF1A73E8), // أزرق صحّتك
    const Color(0xFF34A99F), // تركواز فاتح
    const Color(0xFF08776E), // تركواز داكن
    const Color(0xFF263238), // رمادي داكن
  ];
}
