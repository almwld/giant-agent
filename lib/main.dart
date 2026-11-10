import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'screens/welcome_screen.dart';
import 'screens/agentos_shell.dart';
import 'services/app_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Render Flutter immediately. Do not leave Android on its native black
  // launch window while preferences/plugins initialize.
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final preferences = AppPreferences.instance;
    return AnimatedBuilder(
      animation: preferences,
      builder: (context, _) => MaterialApp(
        title: 'Giant Agent',
        debugShowCheckedModeBanner: false,
        locale: preferences.locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        themeMode: preferences.themeMode,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const _AppStartupGate(),
      ),
    );
  }
}

class _AppStartupGate extends StatefulWidget {
  const _AppStartupGate();

  @override
  State<_AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<_AppStartupGate> {
  bool _ready = false;
  bool _showWelcome = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    var showWelcome = false;
    try {
      await AppPreferences.instance.load();
      final prefs = await SharedPreferences.getInstance();
      showWelcome = !(prefs.getBool('giant_has_launched') ?? false);
      if (showWelcome) {
        await prefs.setBool('giant_has_launched', true);
      }
    } catch (error, stackTrace) {
      // Preferences must never prevent the application from opening.
      debugPrint('Giant Agent startup preferences failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    if (!mounted) return;
    setState(() {
      _showWelcome = showWelcome;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Scaffold(
        backgroundColor: dark ? AppTheme.darkBackground : AppTheme.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(.12),
                  borderRadius: BorderRadius.circular(23),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 40,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Giant Agent',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _showWelcome ? const WelcomeScreen() : const AgentOsShell();
  }
}
