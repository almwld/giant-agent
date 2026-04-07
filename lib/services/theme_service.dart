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
    final colorValue = prefs.getInt(_colorKey) ?? 0xFF6C63FF;
    return Color(colorValue);
  }
  
  static Future<void> setAccentColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_colorKey, color.value);
  }
  
  static List<Color> getAvailableColors() => [
    const Color(0xFF6C63FF), // بنفسجي
    const Color(0xFF10A37F), // أخضر
    const Color(0xFF2196F3), // أزرق
    const Color(0xFFFF9800), // برتقالي
    const Color(0xFFE91E63), // وردي
  ];
}
