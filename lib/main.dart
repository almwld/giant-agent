import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/welcome_screen.dart';
import 'screens/chat_screen.dart';
import 'services/app_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Paint a Flutter frame immediately. Preference/platform-channel startup
  // must never keep Android on its launch window.
  runApp(const StartupGate());
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _ready = false;
  bool _showSplash = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await AppPreferences.instance.load().timeout(
        const Duration(seconds: 5),
      );
    } catch (error, stackTrace) {
      debugPrint('Giant Agent startup [preferences] failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    var showSplash = false;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 5),
      );
      showSplash = !(prefs.getBool('giant_has_launched') ?? false);
      if (showSplash) {
        await prefs.setBool('giant_has_launched', true).timeout(
          const Duration(seconds: 5),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Giant Agent startup [launch-state] failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    if (!mounted) return;
    setState(() {
      _showSplash = showSplash;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return MyApp(showSplash: _showSplash);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF10131B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.dark,
        ),
      ),
      home: const Scaffold(
        backgroundColor: Color(0xFF10131B),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 18),
              Text(
                'جارٍ تجهيز Giant Agent…',
                style: TextStyle(color: Color(0xFFE4E4E7), fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
