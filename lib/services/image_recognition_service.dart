import 'dart:io';

/// Capability boundary for image input.
///
/// The bundled local GGUF runtime is text-only. This service reports file
/// metadata, but deliberately refuses to fabricate visual descriptions or
/// OCR results until a real vision/OCR model is installed and wired.
class ImageRecognitionService {
  static Future<String> analyzeImage(File imageFile) async {
    if (!await imageFile.exists()) {
      throw FileSystemException('Image file does not exist.', imageFile.path);
    }
    final size = await imageFile.length();
    final extension = imageFile.path.split('.').last.toLowerCase();
    return 'تم استلام الصورة دون تحليل بصري. '
        'الحجم: $size بايت؛ النوع: $extension. '
        'يلزم ربط نموذج رؤية فعلي لتحليل محتواها.';
  }

  static Future<String> extractTextFromImage(File imageFile) async {
    if (!await imageFile.exists()) {
      throw FileSystemException('Image file does not exist.', imageFile.path);
    }
    throw UnsupportedError(
      'OCR is not configured. Install and connect a real OCR engine before requesting text extraction.',
    );
  }
}
