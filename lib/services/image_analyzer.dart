import 'dart:io';

import 'image_recognition_service.dart';

/// Compatibility adapter for the image intake flow. No OCR is claimed unless
/// a real OCR engine is configured by ImageRecognitionService.
class ImageAnalyzer {
  static Future<String> analyzeImage(File imageFile) =>
      ImageRecognitionService.analyzeImage(imageFile);
}
