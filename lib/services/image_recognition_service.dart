import 'dart:io';
import 'package:flutter/services.dart';

/// On-device OCR bridge. ML Kit's bundled recognizer is Latin-script only;
/// it does not provide Arabic OCR or semantic image understanding.
class ImageRecognitionService {
  static const MethodChannel _channel = MethodChannel('giant_agent/tools');

  static Future<String> analyzeImage(File imageFile) async {
    final result = await _recognize(imageFile);
    final text = result['text']?.toString() ?? '';
    if (text.trim().isEmpty) {
      return 'تم فحص الصورة بمحرك OCR المحلي، ولم يُعثر على نص قابل للاستخراج. '
          'المحرك الحالي يدعم النصوص اللاتينية فقط ولا يصف محتوى الصورة بصريًا.';
    }

    final rawLines = result['lines'];
    final lines = rawLines is List
        ? rawLines.whereType<Map>().map((line) {
            final value = line['text']?.toString() ?? '';
            final confidence = (line['confidence'] as num?)?.toDouble();
            final box = [
              line['left'], line['top'], line['width'], line['height'],
            ].map((v) => v?.toString() ?? '0').join(',');
            final score = confidence == null
                ? ''
                : ' • ثقة ${(confidence * 100).toStringAsFixed(0)}%';
            return '- $value$score • موضع الصورة: $box';
          }).join('\n')
        : '';

    final rawLabels = result['labels'];
    final labels = rawLabels is List
        ? rawLabels.whereType<Map>().map((label) {
            final name = label['text']?.toString() ?? '';
            final confidence = (label['confidence'] as num?)?.toDouble();
            final score = confidence == null
                ? ''
                : ' • ثقة ${(confidence * 100).toStringAsFixed(0)}%';
            return '- $name$score';
          }).join('\n')
        : '';
    return 'النص المستخرج من الصورة (OCR):\n$text'
        '${lines.isEmpty ? '' : '\n\nتفاصيل الأسطر:\n$lines'}'
        '${labels.isEmpty ? '' : '\n\nتصنيفات المحتوى البصري:\n$labels'}'
        '\n\nحدود التحليل: OCR الحالي للنصوص اللاتينية فقط. '
        'التصنيفات مؤشرات احتمالية من نموذج محلي ولا تمثل وصفًا تفصيليًا أو إثباتًا لمحتوى الصورة.';
  }

  static Future<String> extractTextFromImage(File imageFile) async {
    final result = await _recognize(imageFile);
    return result['text']?.toString() ?? '';
  }

  static Future<Map<String, dynamic>> _recognize(File imageFile) async {
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
    return result;
  }
}
