import 'dart:io';
import 'package:flutter/services.dart';

/// On-device OCR bridge. ML Kit's bundled recognizer is Latin-script only;
/// it does not provide Arabic OCR or semantic image understanding.
class ImageRecognitionService {
  static const MethodChannel _channel = MethodChannel('giant_agent/tools');

  static Future<String> analyzeImage(File imageFile) async {
    final text = await extractTextFromImage(imageFile);
    if (text.trim().isEmpty) {
      return 'تم فحص الصورة بمحرك OCR المحلي، ولم يُعثر على نص قابل للاستخراج. '
          'هذا المحرك يستخرج النصوص اللاتينية فقط ولا يصف محتوى الصورة بصريًا.';
    }
    return 'النص المستخرج من الصورة (OCR):\n$text\n\n'
        'ملاحظة: محرك OCR الحالي يدعم النصوص اللاتينية، ولا يدعم العربية أو فهم المشاهد والأجسام.';
  }

  static Future<String> extractTextFromImage(File imageFile) async {
    if (!await imageFile.exists()) {
      throw FileSystemException('Image file does not exist.', imageFile.path);
    }
    final size = await imageFile.length();
    if (size < 1 || size > 12 * 1024 * 1024) {
      throw FileSystemException('Image must be between 1 byte and 12 MB.', imageFile.path);
    }
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'recognizeText',
      {'path': imageFile.path},
    );
    if (result == null || result['ok'] != true) {
      throw StateError(result?['error']?.toString() ?? 'OCR engine failed.');
    }
    return result['text']?.toString() ?? '';
  }
}
