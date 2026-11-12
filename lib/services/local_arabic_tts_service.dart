import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Fully on-device Arabic neural speech synthesis using the 82M Nabra model
/// exported for sherpa-onnx. The model is downloaded once into app-private
/// storage; inference and playback never call a remote service.
class LocalArabicTtsService {
  LocalArabicTtsService._();

  static final LocalArabicTtsService instance = LocalArabicTtsService._();

  static const String modelRepo =
      'https://huggingface.co/marwanelamami/nabra-82m-sherpa-onnx/resolve/main';
  static const String espeakArchiveUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/espeak-ng-data.tar.bz2';

  final AudioPlayer _player = AudioPlayer();
  final http.Client _client = http.Client();
  sherpa.OfflineTts? _tts;
  Directory? _modelDirectory;
  bool _downloading = false;

  bool get isReady => _tts != null;
  bool get isDownloading => _downloading;

  Future<Directory> _directory() async {
    if (_modelDirectory != null) return _modelDirectory!;
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/voice/nabra-82m-arabic-int8');
    await directory.create(recursive: true);
    _modelDirectory = directory;
    return directory;
  }

  Future<bool> isInstalled() async {
    final dir = await _directory();
    return await File('${dir.path}/model.int8.onnx').exists() &&
        await File('${dir.path}/voices.bin').exists() &&
        await File('${dir.path}/tokens.txt').exists() &&
        await File('${dir.path}/espeak-ng-data/phondata').exists();
  }

  Future<void> _download(
    Uri uri,
    File destination, {
    void Function(double fraction)? onProgress,
  }) async {
    final temporary = File('${destination.path}.part');
    await temporary.parent.create(recursive: true);
    if (await temporary.exists()) await temporary.delete();
    final request = http.Request('GET', uri);
    final response = await _client.send(request);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Model download failed: HTTP ${response.statusCode}', uri: uri);
    }
    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = temporary.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (received == 0 || (total > 0 && received != total)) {
      if (await temporary.exists()) await temporary.delete();
      throw const FormatException('Incomplete voice model download.');
    }
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
  }

  Future<void> install({
    void Function(String file, double fraction)? onProgress,
  }) async {
    if (_downloading) throw StateError('Arabic TTS installation is already running.');
    if (await isInstalled()) return;
    _downloading = true;
    try {
      final dir = await _directory();
      await _download(
        Uri.parse('$modelRepo/model.int8.onnx'),
        File('${dir.path}/model.int8.onnx'),
        onProgress: (p) => onProgress?.call('model.int8.onnx', p),
      );
      await _download(
        Uri.parse('$modelRepo/voices.bin'),
        File('${dir.path}/voices.bin'),
        onProgress: (p) => onProgress?.call('voices.bin', p),
      );
      await _download(
        Uri.parse('$modelRepo/tokens.txt'),
        File('${dir.path}/tokens.txt'),
        onProgress: (p) => onProgress?.call('tokens.txt', p),
      );
      final archiveFile = File('${dir.path}/espeak-ng-data.tar.bz2');
      await _download(
        Uri.parse(espeakArchiveUrl),
        archiveFile,
        onProgress: (p) => onProgress?.call('espeak-ng-data.tar.bz2', p),
      );
      final decoded = BZip2Decoder().decodeBytes(await archiveFile.readAsBytes());
      final archive = TarDecoder().decodeBytes(decoded);
      final espeak = Directory('${dir.path}/espeak-ng-data');
      await espeak.create(recursive: true);
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final parts = entry.name.replaceAll('\\\\', '/').split('/');
        if (parts.any((part) => part == '..')) {
          throw const FormatException('Unsafe path in phonemizer archive.');
        }
        final relative = parts.first == 'espeak-ng-data'
            ? parts.skip(1).join('/')
            : parts.join('/');
        if (relative.isEmpty) continue;
        final output = File('${espeak.path}/$relative');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(entry.content as List<int>, flush: false);
      }
      await archiveFile.delete();
      if (!await isInstalled()) {
        throw StateError('Arabic TTS model package is missing required files.');
      }
    } finally {
      _downloading = false;
    }
  }

  Future<void> initialize() async {
    if (_tts != null) return;
    if (!await isInstalled()) {
      throw StateError('LOCAL_ARABIC_TTS_MODEL_MISSING');
    }
    await sherpa.initBindingsAsync();
    final dir = await _directory();
    final config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        kokoro: sherpa.OfflineTtsKokoroModelConfig(
          model: '${dir.path}/model.int8.onnx',
          voices: '${dir.path}/voices.bin',
          tokens: '${dir.path}/tokens.txt',
          dataDir: '${dir.path}/espeak-ng-data',
          lang: 'ar',
          lengthScale: 1.0,
        ),
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      ),
      maxNumSenetences: 1,
      silenceScale: 0.2,
    );
    _tts = sherpa.OfflineTts(config);
  }

  Future<void> speak(String text, {double speed = 1.0}) async {
    final value = text.trim();
    if (value.isEmpty) return;
    await initialize();
    final dir = await _directory();
    final generated = await Isolate.run(() => _synthesizeNabra({
      'model': '${dir.path}/model.int8.onnx',
      'voices': '${dir.path}/voices.bin',
      'tokens': '${dir.path}/tokens.txt',
      'dataDir': '${dir.path}/espeak-ng-data',
      'text': value,
      'speed': speed,
    }));
    final samples = generated['samples'] as Float32List;
    final sampleRate = generated['sampleRate'] as int;
    if (samples.isEmpty || sampleRate <= 0) {
      throw StateError('Arabic TTS returned an empty audio buffer.');
    }
    final output = File(
      '${dir.path}/speech-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    await output.writeAsBytes(_encodeWave(samples, sampleRate));
    try {
      final completed = _player.onPlayerComplete.first;
      await _player.play(DeviceFileSource(output.path));
      await completed;
    } finally {
      if (await output.exists()) await output.delete();
    }
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() async {
    await stop();
    _tts?.free();
    _tts = null;
    await _player.dispose();
    _client.close();
  }

  static Uint8List _encodeWave(Float32List samples, int sampleRate) {
    final dataLength = samples.length * 2;
    final bytes = ByteData(44 + dataLength);
    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    bytes.setUint32(40, dataLength, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i].clamp(-1.0, 1.0);
      final pcm = (sample < 0 ? sample * 32768 : sample * 32767).round();
      bytes.setInt16(44 + i * 2, pcm, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}

Future<Map<String, Object>> _synthesizeNabra(Map<String, Object> args) async {
  await sherpa.initBindingsAsync();
  final config = sherpa.OfflineTtsConfig(
    model: sherpa.OfflineTtsModelConfig(
      kokoro: sherpa.OfflineTtsKokoroModelConfig(
        model: args['model']! as String,
        voices: args['voices']! as String,
        tokens: args['tokens']! as String,
        dataDir: args['dataDir']! as String,
        lang: 'ar',
        lengthScale: 1.0,
      ),
      numThreads: 2,
      debug: false,
      provider: 'cpu',
    ),
    maxNumSenetences: 1,
    silenceScale: 0.2,
  );
  final engine = sherpa.OfflineTts(config);
  try {
    final audio = engine.generateWithConfig(
      text: args['text']! as String,
      config: sherpa.OfflineTtsGenerationConfig(
        sid: 0,
        speed: args['speed']! as double,
        silenceScale: 0.2,
        extra: const {'lang': 'ar'},
      ),
    );
    return <String, Object>{
      'samples': audio.samples,
      'sampleRate': audio.sampleRate,
    };
  } finally {
    engine.free();
  }
}
