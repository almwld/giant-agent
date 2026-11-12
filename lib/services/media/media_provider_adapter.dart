import 'media_capability.dart';

class MediaProviderResult {
  const MediaProviderResult({
    required this.providerId,
    required this.assets,
    this.message,
    this.metadata = const {},
  });

  final String providerId;
  final List<GeneratedMediaAsset> assets;
  final String? message;
  final Map<String, Object?> metadata;
}

/// Adapter boundary for image/video models.
///
/// Each provider owns its real API contract (authentication, multipart image
/// editing, asynchronous video jobs, polling, and result decoding). Providers
/// must observe request.isCancelled at safe boundaries and abort in-flight
/// network jobs where their transport supports cancellation. Do not assume
/// that a text-chat endpoint can generate or edit media.
abstract interface class MediaProviderAdapter {
  String get id;
  String get displayName;
  Set<MediaCapability> get capabilities;

  Future<MediaProviderResult> execute(MediaTaskRequest request);
}
