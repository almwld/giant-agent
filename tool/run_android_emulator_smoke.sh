#!/usr/bin/env bash
# Run both emulator smoke tests and retain diagnostics without losing shell state.
set +e
flutter test integration_test/gain_pty_emulator_smoke_test.dart -d emulator-5554
pty_status=$?
flutter test integration_test/whisper_arabic_emulator_smoke_test.dart -d emulator-5554
whisper_status=$?
test_status=0
if [ "$pty_status" -ne 0 ] || [ "$whisper_status" -ne 0 ]; then
  test_status=1
fi

echo "===== WHISPER / ANDROID LINKER LOGCAT ====="
adb -s emulator-5554 logcat -d -v threadtime | grep -E -i 'WHISPER_|FlutterWhisper|UnsatisfiedLinkError|dlopen failed|linker|whisper|ggml' | tail -n 300 || true

echo "===== DEBUG APK NATIVE LIBRARY CONTENTS ====="
debug_apk=build/app/outputs/flutter-apk/app-debug.apk
if [ ! -f "$debug_apk" ]; then
  echo "Debug APK was not produced."
  test_status=1
else
  unzip -Z1 "$debug_apk" | grep -E '^lib/(x86_64|arm64-v8a)/lib(whisper|whisper_jni|ggml.*)[.]so$' | sort || true
  if ! unzip -p "$debug_apk" lib/x86_64/libwhisper_jni.so > /tmp/libwhisper_jni.so; then
    echo "Could not extract packaged x86_64 Whisper JNI bridge."
    test_status=1
  elif [ ! -s /tmp/libwhisper_jni.so ]; then
    echo "Packaged Whisper JNI bridge is empty or missing."
    test_status=1
  else
    readelf -Ws /tmp/libwhisper_jni.so > /tmp/whisper-jni-symbols.txt 2>&1
    symbol_count=$(grep -Ec 'Java_io_github_govindtank_flutter_1whisper_WhisperContext_native(Init|Transcribe|Cancel|Free)$' /tmp/whisper-jni-symbols.txt || true)
    grep -E 'Java_io_github_govindtank_flutter_1whisper_WhisperContext_native(Init|Transcribe|Cancel|Free)$' /tmp/whisper-jni-symbols.txt || true
    if [ "$symbol_count" -lt 4 ]; then
      echo "Expected 4 JNI exports, found $symbol_count."
      test_status=1
    fi
  fi
fi

exit "$test_status"
