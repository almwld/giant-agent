import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'gemini_provider.dart';
import 'openai_compatible_provider.dart';

enum ModelProviderMode { local, openRouter, gemini }

class ModelProviderSettings {
  ModelProviderSettings._();
  static final ModelProviderSettings instance = ModelProviderSettings._();
  static const _storage = FlutterSecureStorage();
  static const _modeKey = 'giant_model_provider_mode';

  Future<ModelProviderMode> getMode() async {
    final stored = await _storage.read(key: _modeKey);
    switch (stored) {
      case 'local': return ModelProviderMode.local;
      case 'openrouter': return ModelProviderMode.openRouter;
      case 'gemini': return ModelProviderMode.gemini;
    }
    // One-time compatibility with existing installations that enabled the
    // old OpenRouter toggle before explicit provider modes existed.
    if (await OpenAICompatibleProvider.instance.isEnabled() &&
        !(await OpenAICompatibleProvider.instance.hasLegacyNonOpenRouterEndpoint())) {
      return ModelProviderMode.openRouter;
    }
    if (await GeminiProvider.instance.isEnabled()) {
      return ModelProviderMode.gemini;
    }
    return ModelProviderMode.local;
  }

  Future<void> setMode(ModelProviderMode mode) async {
    await _storage.write(key: _modeKey, value: switch (mode) {
      ModelProviderMode.local => 'local',
      ModelProviderMode.openRouter => 'openrouter',
      ModelProviderMode.gemini => 'gemini',
    });
  }
}
