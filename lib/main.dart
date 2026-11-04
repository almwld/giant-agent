import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
        title: 'Giant Agent', debugShowCheckedModeBanner: false,
        locale: preferences.locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        builder: (context, child) => Directionality(
          textDirection: preferences.locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        ),
        themeMode: preferences.themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6558D3)),
          scaffoldBackgroundColor: const Color(0xFFF5F6FA), useMaterial3: true,
          appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
          cardTheme: CardTheme(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 0),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8D82FF), brightness: Brightness.dark),
          scaffoldBackgroundColor: const Color(0xFF10131B), useMaterial3: true,
          appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
          cardTheme: CardTheme(color: const Color(0xFF1B202C), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 0),
        ),
        home: showSplash ? const WelcomeScreen() : const ChatScreen(),
      ),
    );
  }
}
