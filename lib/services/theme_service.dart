import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();
  
  static const String _themeKey = 'theme_mode';
  
  Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey) ?? 0;
    return ThemeMode.values[themeIndex];
  }
  
  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
  }
  
  static final List<Map<String, dynamic>> themes = [
    {'name': 'Light', 'mode': ThemeMode.light, 'icon': Icons.light_mode},
    {'name': 'Dark', 'mode': ThemeMode.dark, 'icon': Icons.dark_mode},
    {'name': 'System', 'mode': ThemeMode.system, 'icon': Icons.settings},
  ];
  
  static final List<Map<String, dynamic>> accentColors = [
    {'name': 'Green', 'color': Color(0xFF10A37F)},
    {'name': 'Blue', 'color': Color(0xFF2196F3)},
    {'name': 'Purple', 'color': Color(0xFF9C27B0)},
    {'name': 'Orange', 'color': Color(0xFFFF9800)},
    {'name': 'Red', 'color': Color(0xFFF44336)},
    {'name': 'Teal', 'color': Color(0xFF009688)},
  ];
}
