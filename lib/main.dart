import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/welcome_screen.dart';
import 'screens/chat_screen.dart';
import 'widgets/global_voice_orb_overlay_host.dart';
import 'services/app_preferences.dart';
import 'services/notification_service.dart';
import 'services/reminder_service.dart';
import 'services/agent_service.dart';
import 'agent/task_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Render a real Flutter frame before touching databases, native channels,
  // permissions, or the agent runtime. A failed/slow initializer must never
  // leave Android displaying only the black launch window.
  runApp(const GiantAgentBootstrap());
}

class GiantAgentBootstrap extends StatefulWidget {
  const GiantAgentBootstrap({super.key});

  @override
  State<GiantAgentBootstrap> createState() => _GiantAgentBootstrapState();
}

class _GiantAgentBootstrapState extends State<GiantAgentBootstrap> {
  bool _ready = false;
  bool _showSplash = false;

  @override
  void initState() {
    super.initState();
    _initializeApplication();
  }

  Future<void> _attempt(
    String name,
    Future<void> Function() initialize, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      await initialize().timeout(timeout);
    } catch (error, stackTrace) {
      // Startup is best-effort: keep the UI available and retain diagnostics.
      debugPrint('GiantAgent startup [$name] failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _initializeApplication() async {
    await _attempt(
      'preferences',
      () => AppPreferences.instance.load(),
      timeout: const Duration(seconds: 5),
    );

    var showSplash = false;
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      showSplash = !(prefs.getBool('giant_has_launched') ?? false);
      if (showSplash) {
        await prefs.setBool('giant_has_launched', true)
            .timeout(const Duration(seconds: 5));
      }
    } catch (error, stackTrace) {
      debugPrint('GiantAgent startup [launch-state] failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    if (!mounted) return;
    setState(() {
      _showSplash = showSplash;
      _ready = true;
    });

    // The first usable screen is now on display. Restore databases, permissions
    // and the agent runtime in the background; none of them can hold the UI
    // behind the Android launch window or delay opening the chat.
    unawaited(_initializeBackgroundServices());
  }

  Future<void> _initializeBackgroundServices() async {
    await _attempt(
      'notifications',
      () async { await NotificationService.init(); },
      timeout: const Duration(seconds: 8),
    );
    await _attempt(
      'reminders',
      () => ReminderService().init(),
      timeout: const Duration(seconds: 8),
    );
    await _attempt(
      'agent-runtime',
      () => AgentService.instance.initialize(),
      timeout: const Duration(seconds: 20),
    );
    await _attempt(
      'task-recovery',
      () => TaskManager().initialize(),
      timeout: const Duration(seconds: 12),
    );
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
        builder: (context, child) => GlobalVoiceOrbOverlayHost(
          child: child ?? const SizedBox.shrink(),
        ),
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
