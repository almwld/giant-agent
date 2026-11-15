import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'openai_compatible_provider.dart';

/// Available inference backends. Pollinations is a best-effort legacy endpoint.
enum ModelProviderMode { local, openRouter, zeroConfig }

class ModelProviderSettings {
  ModelProviderSettings._();
  static final ModelProviderSettings instance = ModelProviderSettings._();
  static const _storage = FlutterSecureStorage();
  static const _modeKey = 'giant_model_provider_mode';
  Future<void>? _legacyCleanup;

  Future<void> _cleanupLegacyProviders() {
    return _legacyCleanup ??= () async {
      final stored = await _storage.read(key: _modeKey);
      // Remove credentials belonging to retired Gemini integration.
      await _storage.delete(key: 'giant_gemini_api_key');
      await _storage.delete(key: 'giant_gemini_model');
      await _storage.delete(key: 'giant_gemini_enabled');
      // Old non-OpenRouter cloud modes must never silently remain active.
      if (stored == 'gemini') {
        await _storage.write(key: _modeKey, value: 'local');
      }
    }();
  }

  Future<ModelProviderMode> getMode() async {
    await _cleanupLegacyProviders();
    final stored = await _storage.read(key: _modeKey);
    switch (stored) {
      case 'local':
        return ModelProviderMode.local;
      case 'openrouter':
        return ModelProviderMode.openRouter;
      case 'zero_config':
        return ModelProviderMode.zeroConfig;
    }

    // Compatibility with installations that enabled the former OpenRouter
    // toggle before explicit provider modes existed. Arbitrary endpoints are
    // rejected and never activated.
    if (await OpenAICompatibleProvider.instance.isEnabled() &&
        !(await OpenAICompatibleProvider.instance.hasLegacyNonOpenRouterEndpoint())) {
      return ModelProviderMode.openRouter;
    }
    return ModelProviderMode.local;
  }

  Future<void> setMode(ModelProviderMode mode) async {
    await _storage.write(
      key: _modeKey,
      value: switch (mode) {
        ModelProviderMode.local => 'local',
        ModelProviderMode.openRouter => 'openrouter',
        ModelProviderMode.zeroConfig => 'zero_config',
      },
    );
  }
}
