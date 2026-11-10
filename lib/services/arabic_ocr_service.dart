import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

/// Installs and runs the official fast Arabic Tesseract model on-device.
/// The model is downloaded once from the upstream tessdata_fast repository,
/// then all subsequent recognition runs offline.
class ArabicOcrService {
  ArabicOcrService._();
  static final ArabicOcrService instance = ArabicOcrService._();

  static const String _modelUrl =
      'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/ara.traineddata';
  static const int _minimumModelBytes = 500 * 1024;
  Future<void>? _modelInstall;

  Future<String> recognize(File image) async {
    if (!await image.exists()) {
      throw FileSystemException('Image file does not exist.', image.path);
    }
    await _ensureArabicModel();
    final text = await FlutterTesseractOcr.extractText(
      image.path,
      language: 'ara',
      args: const {
        'oem': '1',
        'psm': '11',
        'preserve_interword_spaces': '1',
      },
    ).timeout(const Duration(seconds: 90));
    return _normalizeArabicText(text);
  }

  Future<void> _ensureArabicModel() async {
    final existing = await _modelFile();
    if (await existing.exists() && await existing.length() >= _minimumModelBytes) {
      return;
    }
    _modelInstall ??= _downloadArabicModel(existing);
    try {
      await _modelInstall;
    } catch (_) {
      _modelInstall = null;
      rethrow;
    }
  }

  Future<File> _modelFile() async {
    final tessdataPath = await FlutterTesseractOcr.getTessdataPath();
    final directory = Directory(tessdataPath);
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}ara.traineddata');
  }

  Future<void> _downloadArabicModel(File destination) async {
    final client = http.Client();
    final temporary = File('${destination.path}.download');
    try {
      final response = await client.get(Uri.parse(_modelUrl)).timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode != 200) {
        throw HttpException(
          'تعذر تنزيل بيانات OCR العربية (HTTP ${response.statusCode}).',
        );
      }
      if (response.bodyBytes.length < _minimumModelBytes) {
        throw const FormatException('ملف نموذج OCR العربي غير مكتمل.');
      }
      await temporary.writeAsBytes(response.bodyBytes, flush: true);
      if (await temporary.length() < _minimumModelBytes) {
        throw const FormatException('فشل التحقق من ملف OCR العربي بعد التنزيل.');
      }
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    } finally {
      client.close();
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static String _normalizeArabicText(String value) {
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'[\t ]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
