import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class FilePickerService {
  
  // اختيار أي ملف من الهاتف
  static Future<File?> pickAnyFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      
      if (result != null) {
        return File(result.files.single.path!);
      }
      return null;
    } catch (e) {
      print('خطأ في اختيار الملف: $e');
      return null;
    }
  }
  
  // اختيار ملفات TFLite
  static Future<File?> pickTfliteFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tflite'],
        allowMultiple: false,
      );
      
      if (result != null) {
        return File(result.files.single.path!);
      }
      return null;
    } catch (e) {
      print('خطأ في اختيار TFLite: $e');
      // محاولة استخدام FileType.any كبديل
      return await pickAnyFile();
    }
  }
  
  // اختيار أي ملف نموذج
  static Future<File?> pickModelFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tflite', 'onnx', 'gguf', 'bin', 'pb', 'pth', 'pt'],
        allowMultiple: false,
      );
      
      if (result != null) {
        return File(result.files.single.path!);
      }
      return null;
    } catch (e) {
      // إذا فشل، استخدم FileType.any
      return await pickAnyFile();
    }
  }
  
  // فتح متصفح الملفات الافتراضي
  static Future<void> openFileManager() async {
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (e) {
      print('خطأ: $e');
    }
  }
}
