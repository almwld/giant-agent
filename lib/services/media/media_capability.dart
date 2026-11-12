enum MediaCapability {
  generateImage,
  editImage,
  generateVideo,
  editVideo,
  searchImagesByText,
  searchImagesByImage,
  generateSoundEffects,
  findAssetBboxes,
  cropAndReplicateAssets,
}

class MediaTaskRequest {
  const MediaTaskRequest({
    required this.capability,
    required this.prompt,
    this.inputPaths = const [],
    this.options = const {},
    this.isCancelled,
  });

  final MediaCapability capability;
  final String prompt;
  final List<String> inputPaths;
  final Map<String, Object?> options;
  /// Invocation-scoped cancellation predicate supplied by ModelService.
  /// Providers should abort their transport when possible and check this at
  /// every safe boundary before publishing or persisting an asset.
  final bool Function()? isCancelled;

  void throwIfCancelled() {
    if (isCancelled?.call() == true) {
      throw StateError('Media tool call cancelled.');
    }
  }

  bool get requiresInputMedia =>
      capability == MediaCapability.editImage ||
      capability == MediaCapability.editVideo ||
      capability == MediaCapability.searchImagesByImage ||
      capability == MediaCapability.findAssetBboxes ||
      capability == MediaCapability.cropAndReplicateAssets;
}

class GeneratedMediaAsset {
  const GeneratedMediaAsset({
    required this.mimeType,
    this.localPath,
    this.remoteUrl,
    this.fileName,
    this.metadata = const {},
  });

  final String mimeType;
  final String? localPath;
  final Uri? remoteUrl;
  final String? fileName;
  final Map<String, Object?> metadata;

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
}
