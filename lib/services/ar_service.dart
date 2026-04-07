import 'package:flutter/material.dart';

class ARService {
  static final ARService _instance = ARService._internal();
  factory ARService() => _instance;
  ARService._internal();
  
  // توليد خلفيات ذكية حسب المحادثة
  String getSmartBackground(String sentiment) {
    switch(sentiment) {
      case 'positive':
        return 'assets/backgrounds/positive_bg.png';
      case 'negative':
        return 'assets/backgrounds/negative_bg.png';
      default:
        return 'assets/backgrounds/neutral_bg.png';
    }
  }
  
  // توليد تأثيرات بصرية
  String getVisualEffect(String message) {
    if (message.contains('مرحبا')) return '✨';
    if (message.contains('شكرا')) return '🎉';
    if (message.contains('حزين')) return '💙';
    if (message.contains('رائع')) return '⭐';
    return '💫';
  }
  
  // تحويل النص إلى رموز تعبيرية ذكية
  String addSmartEmojis(String text) {
    if (text.contains('مرحبا')) text += ' 👋';
    if (text.contains('شكرا')) text += ' 🙏';
    if (text.contains('رائع')) text += ' 🌟';
    if (text.contains('حزين')) text += ' 😢';
    if (text.contains('سعيد')) text += ' 😊';
    if (text.contains('ممتاز')) text += ' 🔥';
    if (text.contains('أفهم')) text += ' 🧠';
    if (text.contains('أحب')) text += ' ❤️';
    return text;
  }
}
