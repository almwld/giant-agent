import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'advanced_animations.dart';

class AmazingHome extends StatelessWidget {
  final VoidCallback onStart;
  
  const AmazingHome({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              FadeInWidget(
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'GX',
                      style: TextStyle(
                        fontSize: 60,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              FadeInWidget(
                duration: const Duration(milliseconds: 600),
                child: const Text(
                  'Giant Agent X',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FadeInWidget(
                duration: const Duration(milliseconds: 800),
                child: const Text(
                  'الجيل القادم من الذكاء الاصطناعي',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
              ),
              const SizedBox(height: 20),
              FadeInWidget(
                duration: const Duration(milliseconds: 1000),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.star, size: 16, color: Colors.amber),
                      SizedBox(width: 8),
                      Text('5.0', style: TextStyle(color: Colors.white)),
                      SizedBox(width: 16),
                      Icon(Icons.people, size: 16, color: Colors.white),
                      SizedBox(width: 8),
                      Text('10K+', style: TextStyle(color: Colors.white)),
                      SizedBox(width: 16),
                      Icon(Icons.speed, size: 16, color: Colors.white),
                      SizedBox(width: 8),
                      Text('99.9%', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              FadeInWidget(
                duration: const Duration(milliseconds: 1200),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: PulsingButton(
                    onPressed: onStart,
                    child: const Text(
                      'ابدأ الرحلة 🚀',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
