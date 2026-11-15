# Offline voice model installation

Large speech weights are deliberately **not** bundled into APKs. Bundling the
multilingual Whisper Base model (147,951,465 bytes) and Nabra Arabic TTS archive
adds roughly 200 MB to every ABI package and universal build.

The first local-voice setup downloads the following pinned artifacts over HTTPS
into app-private storage. Whisper's cached or newly downloaded model is checked
against its exact byte count and SHA-256 before native loading; partial downloads
resume through HTTP Range. Both engines then run fully on-device; no audio,
transcript, or synthesis request is sent to a cloud speech service.

| Component | Artifact | Source | License | Integrity |
|---|---|---|---|---|
| Whisper multilingual ASR | `ggml-base.bin` (147,951,465 bytes) | `ggerganov/whisper.cpp` at commit `5359861c739e955e79d9a303bcbc70fb988958b1`, installed by the app's verified downloader | MIT | Exact byte count + SHA-256 `60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe` before JNI initialization |
| Nabra Arabic TTS | `nabra-82m-arabic-int8.tar.bz2` | `k2-fsa/sherpa-onnx` release | Apache-2.0 | SHA-256 `a8608a504b1db4dd538b821409fe50b2d5cf37650c0a8753fa215bd6445e9964` |

A network connection is required only for the initial model installation (or
when the user explicitly reinstalls a missing/corrupt model). After successful
installation, voice recognition and synthesis work offline. The models remain
in app-private storage and are not copied into APK assets.

Do not commit model binaries into Git history or add `assets/voice_models/` to
the Flutter asset manifest.
