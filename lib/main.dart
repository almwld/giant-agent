import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'screens/welcome_screen.dart';
import 'screens/chat_screen.dart';
import 'services/app_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.instance.load();
  final prefs = await SharedPreferences.getInstance();
  final showSplash = !(prefs.getBool('giant_has_launched') ?? false);
  if (showSplash) await prefs.setBool('giant_has_launched', true);
  runApp(MyApp(showSplash: showSplash));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.showSplash});
  final bool showSplash;

  @override
  Widget build(BuildContext context) {
    final preferences = AppPreferences.instance;
    return AnimatedBuilder(
      animation: preferences,
      builder: (context, _) => MaterialApp(
        title: 'Giant Agent',
        debugShowCheckedModeBanner: false,
        locale: preferences.locale,
        supportedLocales: const [
          Locale('ar'),
          Locale('en'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        themeMode: preferences.themeMode,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: showSplash ? const WelcomeScreen() : const ChatScreen(),
      ),
    );
  }
}
