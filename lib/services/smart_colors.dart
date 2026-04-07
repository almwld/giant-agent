import 'dart:math';

class SmartColors {
  static final SmartColors _instance = SmartColors._internal();
  factory SmartColors() => _instance;
  SmartColors._internal();
  
  Color getSmartColor(String text) {
    final hash = text.hashCode.abs();
    final hue = (hash % 360) / 360.0;
    return HSLColor.fromAHSL(1.0, hue, 0.7, 0.6).toColor();
  }
  
  Color getSentimentColor(String sentiment) {
    switch(sentiment) {
      case 'positive':
        return Colors.green;
      case 'negative':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }
  
  List<Color> getGradient(String text) {
    final baseColor = getSmartColor(text);
    return [
      baseColor,
      HSLColor.fromColor(baseColor).withLightness(0.4).toColor(),
    ];
  }
}
