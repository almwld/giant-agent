import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// File picker compatibility helpers. GGUF models are imported into the
/// app-private model directory by LlamaService through Android's SAF bridge.
class FilePickerService {
  static Future<File?> pickAnyFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null || path.isEmpty) {
      throw FileSystemException(
        'The selected provider did not expose a local file path. '
        'Use the in-app document intake for supported text files.',
        result.files.single.name,
      );
    }
    return File(path);
  }

  static Future<File?> pickModelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gguf'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final selected = result.files.single;
    if (!selected.name.toLowerCase().endsWith('.gguf')) {
      throw FormatException('Only GGUF model files are supported.');
    }
    final path = selected.path;
    if (path == null || path.isEmpty) {
      throw FileSystemException(
        'The provider did not expose a local path. Import the model through '
        'the native GGUF importer so it can be copied into private storage.',
        selected.name,
      );
    }
    return File(path);
  }
}
