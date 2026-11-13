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

- ASR: Whisper multilingual `ggml-base.bin`, downloaded once by `WhisperModelManager` into app-private storage (roughly 145 MB).
- Neural Arabic TTS: Nabra-82M INT8 ONNX, `voices.bin`, `tokens.txt`, and shared `espeak-ng-data`. The ONNX file is about 83 MB; the complete install is larger because of phonemizer data.
- Models are downloaded over HTTPS only during installation. Once installed, recognition, synthesis, and playback are local.
- If Nabra is skipped, TTS may use an Android Arabic voice only when Android reports `network_required == false`. Unknown or network-required voices are rejected.

Nabra is an MSA voice with one speaker ID. It is not a general dialect voice-cloning model. The Nabra utterance chunker caps each synthesis segment at 180 characters to stay well below its 510-phoneme input limit and to bound interruption latency.

## Conversation behavior

- The recording stays on-device until the user taps **انتهيت — أرسل كلامي**. Whisper then transcribes the WAV locally and sends the final transcript through the existing chat composer. This Flutter 3.16-compatible recorder integration is push-to-finish rather than partial-token ASR streaming.
- The final transcript is sent through the existing chat send path, so conversation history, request IDs, tool orchestration, and the current model runtime remain shared.
- Visible answer tokens are filtered through the existing tool-call sanitizer before they enter the local speech queue. Tool-call JSON is never spoken.
- Sentence-sized answer chunks are synthesized while the model is still generating.
- The voice overlay provides an explicit interruption action. It stops playback and invalidates pending speech segments before restarting local listening.

## Privacy and limitations

- No audio, transcript, or generated speech is uploaded by these local voice services.
- The initial model downloads require internet access; runtime use after installation does not.
- Microphone capture and TTS playback currently use a half-duplex interaction model. The interruption control is explicit; automatic barge-in while the speaker is playing is not enabled because reliable acoustic echo cancellation and full-duplex VAD are not yet wired into the Flutter audio capture path.
- Whisper base and Nabra INT8 consume meaningful storage and RAM. Low-memory devices should be benchmarked before making these models the default on every device.
- The ASR engine and Nabra synthesis run on native CPU inference. Nabra synthesis is moved to a worker isolate so it does not block Flutter rendering.

## Verification

- `LocalVoiceTextChunker` unit tests cover whitespace, chunk bounds, oversized tokens, and invalid limits.
- CI must verify Flutter dependency resolution, analysis, tests, and release APK builds for the supported Android ABIs.
- Physical-device acceptance still needs to measure Arabic dialect accuracy, first-token latency, real-time factor, peak RAM, thermal behavior, battery drain, and interruption latency.
