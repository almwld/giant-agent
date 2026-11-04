import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences extends ChangeNotifier {
  AppPreferences._();
  static final AppPreferences instance = AppPreferences._();
  static const _themeKey = 'giant_theme_mode';
  static const _localeKey = 'giant_locale';
  ThemeMode _themeMode = ThemeMode.dark;
  Locale _locale = const Locale('ar');
  Locale get locale => _locale;
  ThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString(_themeKey);
    _themeMode = theme == 'light' ? ThemeMode.light : theme == 'system' ? ThemeMode.system : ThemeMode.dark;
    _locale = Locale(prefs.getString(_localeKey) == 'en' ? 'en' : 'ar');
  }

  Future<void> setThemeMode(ThemeMode value) async {
    _themeMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, value == ThemeMode.light ? 'light' : value == ThemeMode.system ? 'system' : 'dark');
    notifyListeners();
  }

  Future<void> setLocale(Locale value) async {
    _locale = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, value.languageCode);
    notifyListeners();
  }
}
