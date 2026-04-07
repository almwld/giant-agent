import 'package:flutter/material.dart';

class DynamicTheme {
  static Color getDynamicColor(String text) {
    final hash = text.hashCode.abs();
    final hue = (hash % 360) / 360.0;
    return HSLColor.fromAHSL(1.0, hue, 0.7, 0.6).toColor();
  }
  
  static List<Color> getGradient(String text) {
    final color = getDynamicColor(text);
    return [color, color.withBlue(255 - color.blue.toInt())];
  }
  
  static IconData getIconForMessage(String message) {
    if (message.contains('مرحبا')) return Icons.waving_hand;
    if (message.contains('شكرا')) return Icons.favorite;
    if (message.contains('كود')) return Icons.code;
    if (message.contains('موقع')) return Icons.web;
    if (message.contains('حلل')) return Icons.analytics;
    if (message.contains('سؤال')) return Icons.help;
    return Icons.chat_bubble;
  }
}
