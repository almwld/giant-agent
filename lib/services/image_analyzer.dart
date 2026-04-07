import 'dart:io';
import 'package:google_ml_kit/google_ml_kit.dart';

class ImageAnalyzer {
  static Future<String> analyzeImage(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final textRecognizer = GoogleMlKit.vision.textRecognizer();
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();
      
      if (recognizedText.text.isNotEmpty) {
        return '📝 النص المستخرج من الصورة:\n${recognizedText.text}';
      }
      return '🖼️ تم تحليل الصورة بنجاح (لم يتم العثور على نص)';
    } catch (e) {
      return '❌ خطأ في تحليل الصورة: $e';
    }
  }
}
