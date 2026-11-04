import 'dart:async';
import 'package:flutter/material.dart';
import 'chat_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}
class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 900), vsync: this)..forward();
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1600), () {
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ChatScreen()));
    });
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(width: double.infinity,
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [colors.primary, colors.primaryContainer])),
        child: FadeTransition(opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
          child: ScaleTransition(scale: Tween<double>(begin: .88, end: 1).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutBack)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 104, height: 104, decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(30)),
                child: Icon(Icons.auto_awesome_rounded, size: 56, color: colors.primary)),
              const SizedBox(height: 28),
              Text('Giant Agent', style: TextStyle(color: colors.onPrimary, fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('الوكيل الذكي المحلي', style: TextStyle(color: colors.onPrimary.withOpacity(.8), fontSize: 15)),
              const SizedBox(height: 32),
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary)),
            ]),
          ),
        ),
      ),
    );
  }
}
