import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/welcome_screen.dart';
import 'screens/chat_screen.dart';
import 'services/app_preferences.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.instance.load();
  await NotificationService.init();
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
        // Let Flutter's localization system provide Directionality to the
        // Navigator and every Material route. A second root Directionality
        // wrapper can override route-level direction and confuse overlays.
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        themeMode: preferences.themeMode,
        theme: ThemeData(
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6558D3),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF5F6FA),
          canvasColor: const Color(0xFFF5F6FA),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
            backgroundColor: Color(0xFFF5F6FA),
            foregroundColor: Color(0xFF20212A),
          ),
          cardTheme: CardTheme(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            elevation: 0,
          ),
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8D82FF),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF10131B),
          canvasColor: const Color(0xFF10131B),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
            backgroundColor: Color(0xFF10131B),
            foregroundColor: Color(0xFFF4F5FA),
          ),
          cardTheme: CardTheme(
            color: const Color(0xFF1B202C),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            elevation: 0,
          ),
        ),
        home: showSplash ? const WelcomeScreen() : const ChatScreen(),
      ),
    );
  }
}
