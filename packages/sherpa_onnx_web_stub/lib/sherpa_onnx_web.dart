import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// The Giant Agent mobile application ships Android only. This no-op web
/// package exists solely to satisfy sherpa_onnx's conditional package import;
/// it deliberately does not provide WebAssembly inference.
class SherpaOnnxWeb {
  static void registerWith(Registrar registrar) {}

  static Future<void> loadWasm() async {
    throw UnsupportedError('sherpa_onnx web inference is not included in this Android app.');
  }
}
