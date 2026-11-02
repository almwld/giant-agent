import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GatewaySettings {
  GatewaySettings({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _urlKey = 'assistant_gateway_url';
  static const _tokenKey = 'assistant_gateway_token';
  static const _modelKey = 'assistant_model_id';

  Future<String> get baseUrl async => (await _storage.read(key: _urlKey))?.trim() ?? '';
  Future<String?> get accessToken async => _storage.read(key: _tokenKey);
  Future<String?> get model async => _storage.read(key: _modelKey);

  Future<bool> get isConfigured async {
    final url = await baseUrl;
    final token = await accessToken;
    return url.isNotEmpty && token != null && token.isNotEmpty;
  }

  Future<void> save({required String url, required String token, required String model}) async {
    final normalized = url.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty ||
        (uri.scheme != 'https' && uri.host != 'localhost' && uri.host != '10.0.2.2')) {
      throw const FormatException('أدخل عنوان HTTPS صالحاً للخادم.');
    }
    if (token.trim().length < 16) {
      throw const FormatException('رمز الوصول غير صالح أو قصير جداً.');
    }
    await _storage.write(key: _urlKey, value: normalized);
    await _storage.write(key: _tokenKey, value: token.trim());
    await _storage.write(key: _modelKey, value: model.trim().isEmpty ? 'openrouter/free' : model.trim());
  }

  Future<void> clear() async {
    await _storage.delete(key: _urlKey);
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _modelKey);
  }
}
