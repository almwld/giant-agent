import 'package:flutter_secure_storage/flutter_secure_storage.dart';
class GatewaySettings {
  GatewaySettings({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _urlKey='assistant_gateway_url', _tokenKey='assistant_gateway_token',
      _modelKey='assistant_model_id', _providerKey='assistant_provider', _apiKeyKey='assistant_provider_api_key';
  Future<String> get baseUrl async => (await _storage.read(key:_urlKey))?.trim() ?? '';
  Future<String?> get accessToken async => _storage.read(key:_tokenKey);
  Future<String?> get model async => _storage.read(key:_modelKey);
  Future<String> get provider async => (await _storage.read(key:_providerKey)) ?? 'openrouter';
  Future<String?> get providerApiKey async => _storage.read(key:_apiKeyKey);
  Future<bool> get isConfigured async {
    final url=await baseUrl, token=await accessToken, key=await providerApiKey;
    return url.isNotEmpty && token!=null && token.isNotEmpty && key!=null && key.isNotEmpty;
  }
  Future<void> save({required String url, required String token, required String provider,
      required String apiKey, required String model}) async {
    final normalized=url.trim().replaceFirst(RegExp(r'/+$'),'');
    final uri=Uri.tryParse(normalized);
    if(uri==null || uri.host.isEmpty || (uri.scheme!='https' && uri.host!='localhost' && uri.host!='10.0.2.2')) {
      throw const FormatException('أدخل عنوان HTTPS صالحاً للخادم.');
    }
    if(token.trim().length<16) throw const FormatException('رمز الوصول للبوابة غير صالح أو قصير جداً.');
    if(apiKey.trim().length<8) throw const FormatException('أدخل مفتاح API صالحاً للمزود المحدد.');
    if(!const ['openrouter','gemini','openai'].contains(provider)) throw const FormatException('مزود غير مدعوم.');
    await _storage.write(key:_urlKey,value:normalized);
    await _storage.write(key:_tokenKey,value:token.trim());
    await _storage.write(key:_providerKey,value:provider);
    await _storage.write(key:_apiKeyKey,value:apiKey.trim());
    await _storage.write(key:_modelKey,value:model.trim().isEmpty?'openrouter/free':model.trim());
  }
  Future<void> clear() async {
    for(final key in [_urlKey,_tokenKey,_modelKey,_providerKey,_apiKeyKey]) { await _storage.delete(key:key); }
  }
}
