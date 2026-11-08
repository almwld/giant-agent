import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/giant_palette.dart';
import 'chat_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 1000),
    vsync: this,
  )..forward();

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1700), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChatScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GiantPalette.background,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              GiantPalette.background,
              Color(0xFF102B28),
              GiantPalette.background,
            ],
            stops: [0, .52, 1],
          ),
        ),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: .88, end: 1).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    color: GiantPalette.surface,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: GiantPalette.primaryLight.withOpacity(.55),
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: GiantPalette.primary.withOpacity(.22),
                        blurRadius: 34,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: _GiantMark(),
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'Giant Agent',
                  style: TextStyle(
                    color: GiantPalette.text,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .3,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'الوكيل الذكي المحلي',
                  style: TextStyle(
                    color: GiantPalette.muted,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 34),
                const SizedBox(
                  width: 23,
                  height: 23,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: GiantPalette.primaryLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GiantMark extends StatelessWidget {
  const _GiantMark();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.auto_awesome_rounded,
      size: 58,
      color: GiantPalette.primaryLight,
    );
  }
}
