import 'media_capability.dart';
import 'media_provider_adapter.dart';

class MediaProviderRegistry {
  MediaProviderRegistry._();
  static final MediaProviderRegistry instance = MediaProviderRegistry._();

  final Map<String, MediaProviderAdapter> _providers = {};

  List<MediaProviderAdapter> get providers =>
      List.unmodifiable(_providers.values);

  void register(MediaProviderAdapter provider) {
    final id = provider.id.trim();
    if (id.isEmpty) throw ArgumentError.value(provider.id, 'provider.id');
    _providers[id] = provider;
  }

  void unregister(String providerId) => _providers.remove(providerId);

  List<MediaProviderAdapter> providersFor(MediaCapability capability) =>
      _providers.values
          .where((provider) => provider.capabilities.contains(capability))
          .toList(growable: false);

  Future<MediaProviderResult> execute(
    MediaTaskRequest request, {
    String? providerId,
  }) async {
    if (request.prompt.trim().isEmpty) {
      throw ArgumentError('يجب إدخال وصف للعملية الإعلامية.');
    }
    if (request.requiresInputMedia && request.inputPaths.isEmpty) {
      throw ArgumentError('هذه العملية تحتاج إلى ملف صورة أو فيديو مصدر.');
    }

    final provider = providerId == null
        ? providersFor(request.capability).firstOrNull
        : _providers[providerId];
    if (provider == null ||
        !provider.capabilities.contains(request.capability)) {
      throw StateError(
        'لا يوجد مزوّد متصل يدعم العملية: ${request.capability.name}.',
      );
    }
    return provider.execute(request);
  }
}
