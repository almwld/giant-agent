# Bundled offline voice models

The release APKs include both pinned speech models as Flutter assets. CI downloads
the model artifacts at build time, verifies their SHA-256 digests (and Whisper's
exact byte count), and packages them into all three ABI APKs. The app does not
download speech models after launch.

At first use, the app decompresses the bundled Whisper `.gz` asset and writes the restored model into app-private storage
because flutter_whisper requires a filesystem path, and extracts the bundled
Nabra archive into app-private storage for sherpa-onnx. This is local extraction
from the installed APK, not a network download. Both engines then run offline.

| Component | Bundled artifact | Integrity | License |
|---|---|---|---|
| Whisper multilingual ASR | `ggml-base.bin.gz` (gzip level 9; restores to 147,951,465 bytes) | SHA-256 `60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe` | MIT |
| Nabra Arabic TTS | `nabra-82m-arabic-int8.tar.bz2` (upstream bzip2-compressed archive; retained without wasteful recompression) | SHA-256 `a8608a504b1db4dd538b821409fe50b2d5cf37650c0a8753fa215bd6445e9964` | Apache-2.0 |

APK size increases substantially because the speech models are now included.
CI checks that both assets exist in every ABI output and uses a higher diagnostic
size ceiling. Model binaries are fetched by the build script, not committed to Git.
