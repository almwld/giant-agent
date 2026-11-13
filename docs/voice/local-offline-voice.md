# Local offline Arabic voice conversation

## Runtime

The chat voice button now uses an on-device speech pipeline:

```text
Microphone
  -> whisper.cpp (multilingual GGML base, Arabic)
  -> existing ChatScreen session and AgentService/ModelService runtime
  -> existing local DeepSeek/GGUF model and agent tools
  -> streamed visible answer chunks
  -> Nabra-82M INT8 (sherpa-onnx/Kokoro) or an explicitly offline Android Arabic voice
  -> local audio playback
```

No voice request is sent to a cloud speech API. The old `speech_to_text` dependency was removed from the chat voice path because the Android speech-recognition service can route audio to a network service depending on device configuration.

## First-run model setup

- ASR: Whisper multilingual Base, downloaded once by `flutter_whisper` into app-private storage (roughly 143 MB).
- Neural Arabic TTS: The official `nabra-82m-arabic-int8.tar.bz2` archive from sherpa-onnx, containing the 83 MB INT8 ONNX model, `voices.bin`, `tokens.txt`, and `espeak-ng-data`. The archive SHA-256 is checked before extraction.
- Models are downloaded over HTTPS only during installation. Once installed, recognition, synthesis, and playback are local.
- If Nabra is skipped, TTS may use an Android Arabic voice only when Android reports `network_required == false`. Unknown or network-required voices are rejected.

Nabra is an MSA voice with one speaker ID. It is not a general dialect voice-cloning model. The Nabra utterance chunker caps each synthesis segment at 100 characters to stay well below its 510-phoneme input limit and to bound interruption latency.

## Conversation behavior

- The recording stays on-device until the user taps **انتهيت — أرسل كلامي**. Whisper then transcribes the WAV locally and sends the final transcript through the existing chat composer. This Flutter 3.16-compatible recorder integration is push-to-finish rather than partial-token ASR streaming.
- The final transcript is sent through the existing chat send path and current local GGUF runtime. Voice mode refuses to start without a loaded local model; if OpenRouter is selected, it asks before temporarily switching to local and restores the prior provider when the overlay closes.
- Voice requests bypass web search, GitHub context, and agent/tool execution so this path does not invoke remote APIs.
- Visible answer tokens are filtered through the existing tool-call sanitizer before they enter the local speech queue. Tool-call JSON is never spoken.
- Sentence-sized answer chunks are synthesized while the model is still generating.
- The voice overlay provides an explicit interruption action. It stops playback and invalidates pending speech segments before restarting local listening.

## Privacy and limitations

- No audio, transcript, or generated speech is uploaded by these local voice services.
- The initial model downloads require internet access; runtime use after installation does not.
- Microphone capture and TTS playback currently use a half-duplex interaction model. The interruption control is explicit; automatic barge-in while the speaker is playing is not enabled because reliable acoustic echo cancellation and full-duplex VAD are not yet wired into the Flutter audio capture path.
- Whisper base and Nabra INT8 consume meaningful storage and RAM. Low-memory devices should be benchmarked before making these models the default on every device.
- The ASR engine and Nabra synthesis run on native CPU inference. A persistent worker isolate keeps one Nabra engine loaded and prevents synthesis from blocking Flutter rendering.
- Upstream sherpa-onnx has an open Nabra/Kokoro issue involving a 510-phoneme boundary and internal syllable-dot handling (issue #4057). This implementation uses conservative 100-character chunks to reduce the boundary risk, but it does not claim the upstream phonemizer issue is fixed. Arabic audio quality and stability must be validated on physical devices before production rollout.

## Verification

- `LocalVoiceTextChunker` unit tests cover whitespace, chunk bounds, oversized tokens, and invalid limits.
- CI must verify Flutter dependency resolution, analysis, tests, and release APK builds for the supported Android ABIs.
- Physical-device acceptance still needs to measure Arabic dialect accuracy, first-token latency, real-time factor, peak RAM, thermal behavior, battery drain, and interruption latency.
