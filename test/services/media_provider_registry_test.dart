import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/services/media/media_capability.dart';
import 'package:giant_agent_x/services/media/media_provider_adapter.dart';
import 'package:giant_agent_x/services/media/media_provider_registry.dart';

class _FakeMediaProvider implements MediaProviderAdapter {
  @override
  String get id => 'fake-image-provider';
  @override
  String get displayName => 'Fake image provider';
  @override
  Set<MediaCapability> get capabilities => {MediaCapability.generateImage};

  @override
  Future<MediaProviderResult> execute(MediaTaskRequest request) async {
    return MediaProviderResult(
      providerId: id,
      assets: const [
        GeneratedMediaAsset(mimeType: 'image/png', fileName: 'generated.png'),
      ],
    );
  }
}

void main() {
  late MediaProviderRegistry registry;

  setUp(() {
    registry = MediaProviderRegistry.instance;
    registry.unregister('fake-image-provider');
  });

  test('rejects media capabilities that have no connected provider', () async {
    await expectLater(
      registry.execute(const MediaTaskRequest(
        capability: MediaCapability.generateVideo,
        prompt: 'A short clip',
      )),
      throwsA(isA<StateError>()),
    );
  });

  test('requires a source asset for editing tasks', () async {
    registry.register(_FakeMediaProvider());
    await expectLater(
      registry.execute(const MediaTaskRequest(
        capability: MediaCapability.editImage,
        prompt: 'Remove the background',
      )),
      throwsArgumentError,
    );
  });

  test('image search, sound and asset operations remain provider-gated', () async {
    expect(MediaTaskRequest(
      capability: MediaCapability.searchImagesByImage,
      prompt: 'Find similar images',
    ).requiresInputMedia, isTrue);
    expect(MediaTaskRequest(
      capability: MediaCapability.findAssetBboxes,
      prompt: 'Find object bounds',
    ).requiresInputMedia, isTrue);
    expect(MediaTaskRequest(
      capability: MediaCapability.cropAndReplicateAssets,
      prompt: 'Crop the icon',
    ).requiresInputMedia, isTrue);

    await expectLater(
      registry.execute(const MediaTaskRequest(
        capability: MediaCapability.generateSoundEffects,
        prompt: 'A short notification chime',
      )),
      throwsA(isA<StateError>()),
    );
  });

  test('routes an image generation request to a capable provider', () async {
    registry.register(_FakeMediaProvider());
    final result = await registry.execute(const MediaTaskRequest(
      capability: MediaCapability.generateImage,
      prompt: 'A glass sphere',
    ));
    expect(result.providerId, 'fake-image-provider');
    expect(result.assets.single.mimeType, 'image/png');
  });
}
