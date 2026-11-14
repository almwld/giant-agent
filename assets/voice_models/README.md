# Bundled offline voice models

The Android Gradle task `prepareVoiceModels` downloads these pinned model artifacts before Flutter compiles the asset bundle. The APK therefore contains the weights; the app only copies/extracts them into its private support directory on first use and never downloads them at runtime.

| Component | Bundled artifact | Source | License | Integrity |
|---|---|---|---|---|
| Whisper multilingual ASR | `ggml-base.bin` (147,951,465 bytes) | `ggerganov/whisper.cpp` | MIT | SHA-256 `60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe` |
| Nabra Arabic TTS | `nabra-82m-arabic-int8.tar.bz2` | `k2-fsa/sherpa-onnx` release | Apache-2.0 | SHA-256 `e7c644fabb1529190de9a2f7d6044f88c26bf6d9b717ad41ef5d2b748e01459b` |

The full multilingual Whisper Base model is retained (not the English-only Tiny model). Nabra INT8 is retained for cleaner speech output. The compressed Nabra archive includes the ONNX model, voice vectors, phoneme tokens, and eSpeak-NG Arabic data.

Do not commit model binaries into Git history. The build task retrieves them, verifies their exact hashes, and packages them into each APK/AAB.
