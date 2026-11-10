import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/welcome_screen.dart';
import 'screens/chat_screen.dart';
import 'services/app_preferences.dart';
import 'services/notification_service.dart';
import 'services/reminder_service.dart';
import 'services/agent_service.dart';
import 'agent/task_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.instance.load();
  await NotificationService.init();
  await ReminderService().init();
  // Reconcile durable request and task state before exposing the UI.
  await AgentService.instance.initialize();
  await TaskManager().initialize();
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
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xB90D8078),
            elevation: 0,
            insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0x5575E0D2), width: 0.8),
            ),
            contentTextStyle: const TextStyle(
              color: Color(0xFFF0FFFC),
              fontSize: 13,
              height: 1.35,
            ),
          ),
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
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xD9108178),
            elevation: 0,
            insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0x5575E0D2), width: 0.8),
            ),
            contentTextStyle: const TextStyle(
              color: Color(0xFFF0FFFC),
              fontSize: 13,
              height: 1.35,
            ),
          ),
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
