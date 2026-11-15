# Physical Android voice acceptance

Run this on a real Android phone (not an emulator) after installing the split APK
for the device ABI and allowing microphone/audio permissions:

```bash
flutter pub get
sudo apt-get install -y espeak-ng sox
mkdir -p integration_test/fixtures
espeak-ng -v ar -s 125 -w integration_test/fixtures/arabic_smoke_raw.wav "السلام عليكم"
sox integration_test/fixtures/arabic_smoke_raw.wav -r 16000 -c 1 -b 16 -e signed-integer integration_test/fixtures/arabic_smoke.wav
rm integration_test/fixtures/arabic_smoke_raw.wav
python3 tool/patch_flutter_whisper.py
flutter test integration_test/voice_device_acceptance_test.dart -d <ANDROID_DEVICE_ID>
```

The test installs/verifies the local Whisper and Nabra models, runs Arabic WAV
inference, performs Nabra synthesis and playback, and prints ASR/TTS elapsed
milliseconds plus process RSS before/after inference. Save the full test log with
the phone model, Android version, ABI, available RAM, battery level, and ambient
temperature. Repeat at least three times after a cold app launch.

Do not mark physical-device acceptance complete until the logs demonstrate:
- Arabic language detection and non-empty Arabic-script transcription.
- Successful Nabra synthesis and audible playback.
- No crash, ANR, or native worker leak across three cold runs.
- RSS and latency recorded on the target device; agree device-specific
  budgets before setting a universal threshold (low-end Android devices vary).
- Microphone-route, Bluetooth/headset, thermal and battery behavior reviewed.

The repository CI emulator job is a smoke test, not a substitute for this
physical-device acceptance.
