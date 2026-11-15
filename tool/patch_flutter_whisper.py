#!/usr/bin/env python3
"""Apply Giant Agent's narrow WAV-only fix to flutter_whisper's missing miniaudio header.

The app's recorder writes canonical 16 kHz mono PCM16 WAV files. The upstream
JNI bridge unnecessarily uses miniaudio to decode many formats, but the
published plugin archive omits miniaudio.h. This patch replaces that decoder
with a strict RIFF/WAVE PCM16 reader; it does not change Whisper inference.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

MARKER = "// GIANT_AGENT_WAV_ONLY_DECODER"
MINIAUDIO_BLOCK = '''#define MA_NO_DEVICE_IO
#define MA_NO_THREADING
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"'''

DECODER = r"""
// GIANT_AGENT_WAV_ONLY_DECODER
// AudioRecord in flutter_whisper writes 16 kHz mono PCM16 WAV. Parse that
// exact format directly so the Android build has no undeclared miniaudio
// header dependency and malformed/unsupported audio fails closed.
static bool load_audio_16k(const std::string& path, std::vector<float>& out) {
    std::ifstream input(path, std::ios::binary);
    if (!input) return false;

    char riff[4] = {};
    char wave[4] = {};
    uint32_t riffSize = 0;
    auto readU16 = [&input](uint16_t& value) -> bool {
        unsigned char b[2] = {};
        if (!input.read(reinterpret_cast<char*>(b), 2)) return false;
        value = static_cast<uint16_t>(b[0] | (static_cast<uint16_t>(b[1]) << 8));
        return true;
    };
    auto readU32 = [&input](uint32_t& value) -> bool {
        unsigned char b[4] = {};
        if (!input.read(reinterpret_cast<char*>(b), 4)) return false;
        value = static_cast<uint32_t>(b[0]) |
                (static_cast<uint32_t>(b[1]) << 8) |
                (static_cast<uint32_t>(b[2]) << 16) |
                (static_cast<uint32_t>(b[3]) << 24);
        return true;
    };

    if (!input.read(riff, 4) || !readU32(riffSize) ||
        !input.read(wave, 4) ||
        std::memcmp(riff, "RIFF", 4) != 0 ||
        std::memcmp(wave, "WAVE", 4) != 0 || riffSize < 36) {
        return false;
    }

    bool haveFormat = false;
    bool haveData = false;
    uint16_t audioFormat = 0;
    uint16_t channels = 0;
    uint16_t blockAlign = 0;
    uint16_t bitsPerSample = 0;
    uint32_t sampleRate = 0;
    std::vector<unsigned char> pcm;

    while (input && !(haveFormat && haveData)) {
        char chunkId[4] = {};
        uint32_t chunkSize = 0;
        if (!input.read(chunkId, 4) || !readU32(chunkSize)) break;
        const std::streampos chunkStart = input.tellg();
        if (chunkStart < 0) return false;

        if (std::memcmp(chunkId, "fmt ", 4) == 0) {
            uint32_t byteRate = 0;
            if (chunkSize < 16 ||
                !readU16(audioFormat) ||
                !readU16(channels) ||
                !readU32(sampleRate) ||
                !readU32(byteRate) ||
                !readU16(blockAlign) ||
                !readU16(bitsPerSample)) {
                return false;
            }
            haveFormat = true;
        } else if (std::memcmp(chunkId, "data", 4) == 0) {
            if (chunkSize == 0 || chunkSize > 512u * 1024u * 1024u) return false;
            pcm.resize(chunkSize);
            if (!input.read(reinterpret_cast<char*>(pcm.data()),
                            static_cast<std::streamsize>(pcm.size()))) {
                return false;
            }
            haveData = true;
        }

        const std::streamoff paddedSize =
            static_cast<std::streamoff>(chunkSize + (chunkSize & 1u));
        input.clear();
        input.seekg(chunkStart + paddedSize);
    }

    if (!haveFormat || !haveData || audioFormat != 1 || channels != 1 ||
        sampleRate != 16000 || bitsPerSample != 16 || blockAlign != 2 ||
        pcm.empty() || (pcm.size() % 2) != 0) {
        std::fprintf(stderr,
            "WHISPER_WAV_DIAG: fmt=%d data=%d format=%u channels=%u rate=%u bits=%u align=%u bytes=%zu riff=%u\\n",
            haveFormat ? 1 : 0, haveData ? 1 : 0, audioFormat, channels,
            sampleRate, bitsPerSample, blockAlign, pcm.size(), riffSize);
        return false;
    }

    out.clear();
    out.reserve(pcm.size() / 2);
    for (size_t i = 0; i < pcm.size(); i += 2) {
        const uint16_t raw = static_cast<uint16_t>(
            pcm[i] | (static_cast<uint16_t>(pcm[i + 1]) << 8));
        const int32_t signedSample =
            raw < 0x8000u ? static_cast<int32_t>(raw)
                          : static_cast<int32_t>(raw) - 0x10000;
        out.push_back(static_cast<float>(signedSample) / 32768.0f);
    }
    return !out.empty();
}
"""

def package_root(project: Path) -> Path:
    config = project / ".dart_tool" / "package_config.json"
    if not config.is_file():
        raise RuntimeError("Run flutter pub get before applying the Whisper native patch.")
    data = json.loads(config.read_text(encoding="utf-8"))
    for package in data.get("packages", []):
        if package.get("name") == "flutter_whisper":
            uri = urlparse(package["rootUri"])
            if uri.scheme == "file":
                return Path(unquote(uri.path)).resolve()
            return (config.parent / package["rootUri"]).resolve()
    raise RuntimeError("flutter_whisper is not present in package_config.json")

def patch_source(source: str) -> str:
    if MARKER in source:
        return source
    if MINIAUDIO_BLOCK not in source:
        raise RuntimeError("Unexpected flutter_whisper JNI source: miniaudio include block not found.")
    start = source.find("// ---- audio decode:")
    end = source.find("// ---- JSON helpers ----")
    if start < 0 or end < 0 or end <= start:
        raise RuntimeError("Unexpected flutter_whisper JNI source: audio decoder section boundaries not found.")

    # Replace the entire section, not only the function body. This is
    # intentionally anchored on stable section markers to avoid leaving
    # orphaned miniaudio declarations in the compiled translation unit.
    source = source[:start] + DECODER.strip() + "\n\n" + source[end:]
    source = source.replace(MINIAUDIO_BLOCK, "// miniaudio is not required for canonical PCM16 WAV input.")
    source = source.replace("#include <cstring>", "#include <cstring>\n#include <cstdio>\n#include <cstdint>\n#include <fstream>")
    if ('#include "miniaudio.h"' in source or "MINIAUDIO_IMPLEMENTATION" in source or
            "ma_decoder_init_file(" in source or "ma_decoder_read_pcm_frames(" in source or
            "ma_decoder_uninit(" in source):
        raise RuntimeError("miniaudio references remain after applying the WAV decoder patch.")
    return source


def patch_android_abis(gradle: str) -> str:
    """Build the Whisper JNI library for physical ARM devices and x86_64 CI emulators."""
    expected = 'abiFilters "arm64-v8a", "armeabi-v7a"'
    replacement = 'abiFilters "arm64-v8a", "armeabi-v7a", "x86_64"'
    if replacement in gradle:
        return gradle
    if expected not in gradle:
        raise RuntimeError("Unexpected flutter_whisper Android Gradle config: ABI filter declaration not found.")
    return gradle.replace(expected, replacement, 1)


def patch_whisper_context_libraries(root: Path) -> bool:
    """Load GGML, the upstream engine, and the distinct JNI bridge sonames.

    whisper.cpp builds its own shared libwhisper.so on Android. The plugin's
    JNI target must therefore be libwhisper_jni.so; giving both targets the
    OUTPUT_NAME "whisper" causes the packaged engine library to shadow the JNI
    bridge and produces "No implementation found" for nativeInit.
    """
    context = root / "android" / "src" / "main" / "kotlin" / "io" / "github" / "govindtank" / "flutter_whisper" / "WhisperContext.kt"
    if not context.is_file():
        raise RuntimeError(f"WhisperContext Kotlin source not found: {context}")
    cmake = root / "android" / "src" / "main" / "cpp" / "CMakeLists.txt"
    if not cmake.is_file():
        raise RuntimeError(f"Whisper CMake file not found: {cmake}")

    cmake_source = cmake.read_text(encoding="utf-8")
    if "libggml-cpu.so" not in cmake_source or "libggml.so" not in cmake_source:
        raise RuntimeError("Unexpected Whisper CMake config: expected libggml-cpu.so -> libggml.so packaging rule.")
    old_output = "set_target_properties(whisper_jni PROPERTIES OUTPUT_NAME whisper)"
    new_output = "set_target_properties(whisper_jni PROPERTIES OUTPUT_NAME whisper_jni)"
    changed = False
    if old_output in cmake_source:
        cmake_source = cmake_source.replace(old_output, new_output, 1)
        changed = True
    elif new_output not in cmake_source:
        raise RuntimeError("Unexpected Whisper CMake config: JNI bridge output name is not recognized.")
    if changed:
        cmake.write_text(cmake_source, encoding="utf-8")
        print(f"Patched {cmake}: keep upstream libwhisper.so separate from libwhisper_jni.so.")

    source = context.read_text(encoding="utf-8")
    if 'System.loadLibrary("ggml-cpu")' in source:
        source = source.replace('System.loadLibrary("ggml-cpu")', 'System.loadLibrary("ggml")', 1)
        changed = True
    elif 'System.loadLibrary("ggml")' not in source:
        raise RuntimeError("Unexpected WhisperContext Kotlin source: GGML load declaration not found.")

    engine_load = 'System.loadLibrary("whisper")'
    bridge_load = 'System.loadLibrary("whisper_jni")'
    if engine_load not in source:
        raise RuntimeError("Unexpected WhisperContext Kotlin source: upstream whisper engine load declaration not found.")
    if bridge_load not in source:
        source = source.replace(engine_load, engine_load + chr(10) + "        " + bridge_load, 1)
        changed = True
    if changed:
        context.write_text(source, encoding="utf-8")
        print(f"Patched {context}: load libwhisper.so engine then libwhisper_jni.so JNI bridge.")
    return changed


def patch_plugin_native_diagnostics(root: Path) -> bool:
    """Preserve the original Android linker error across the Flutter channel."""
    plugin = root / "android" / "src" / "main" / "kotlin" / "io" / "github" / "govindtank" / "flutter_whisper" / "FlutterWhisperPlugin.kt"
    if not plugin.is_file():
        raise RuntimeError(f"Whisper plugin Kotlin source not found: {plugin}")
    source = plugin.read_text(encoding="utf-8")
    old = '''        } catch (e: UnsatisfiedLinkError) {
            Log.e("FlutterWhisper", "Native whisper library missing", e)
            result.error("NATIVE_NOT_BUILT", "whisper.cpp native library not bundled yet", null)
'''
    new = '''        } catch (e: UnsatisfiedLinkError) {
            val diagnostic = e.toString() + "\\n" + Log.getStackTraceString(e)
            Log.e("FlutterWhisper", "Native whisper library load failed: $diagnostic", e)
            result.error("NATIVE_LINK_ERROR", diagnostic, diagnostic)
'''
    if new in source:
        return False
    if old not in source:
        raise RuntimeError("Unexpected FlutterWhisperPlugin.kt: UnsatisfiedLinkError handler not found.")
    plugin.write_text(source.replace(old, new, 1), encoding="utf-8", newline="\n")
    print(f"Patched {plugin}: preserve the exact native linker error.")
    return True


def prepare_native_engine(root: Path) -> None:
    """Provision upstream whisper.cpp sources and enable the emulator ABI.

    The published plugin contains its JNI/CMake glue but intentionally keeps
    whisper.cpp out of the package archive. Its own fetch script provisions the
    required source tree. Without it, no libwhisper.so is produced.
    """
    source_root = root / "third_party" / "whisper.cpp"
    if not (source_root / "CMakeLists.txt").is_file():
        fetch_script = root / "scripts" / "fetch_whisper_cpp.sh"
        if not fetch_script.is_file():
            raise RuntimeError("flutter_whisper source archive is missing scripts/fetch_whisper_cpp.sh.")
        subprocess.run(["sh", str(fetch_script)], cwd=root, check=True)
    if not (source_root / "CMakeLists.txt").is_file():
        raise RuntimeError("whisper.cpp source provisioning completed without third_party/whisper.cpp/CMakeLists.txt.")

    gradle = root / "android" / "build.gradle"
    if not gradle.is_file():
        raise RuntimeError("flutter_whisper Android Gradle file is missing.")
    original = gradle.read_text(encoding="utf-8")
    patched = patch_android_abis(original)
    if patched != original:
        gradle.write_text(patched, encoding="utf-8", newline="\n")
        print("Patched flutter_whisper Android ABI filters: arm64-v8a, armeabi-v7a, x86_64.")
    else:
        print("flutter_whisper Android ABI filters already include x86_64.")



def patch_jni_symbol_mangling(source: str) -> str:
    """Escape the underscore in the Kotlin package name per JNI name mangling."""
    old_prefix = "Java_io_github_govindtank_flutter_whisper_WhisperContext_"
    new_prefix = "Java_io_github_govindtank_flutter_1whisper_WhisperContext_"
    if old_prefix in source:
        source = source.replace(old_prefix, new_prefix)
        print("Patched Whisper JNI exports: escaped package underscore as _1.")
    required = ("nativeInit", "nativeTranscribe", "nativeCancel", "nativeFree")
    missing = [method for method in required if new_prefix + method not in source]
    if missing:
        raise RuntimeError(
            "Whisper JNI exports do not match Kotlin package "
            "io.github.govindtank.flutter_whisper: " + ", ".join(missing)
        )
    return source


def patch_whisper_model_metadata(root: Path) -> bool:
    """Correct upstream metadata: ggml-base.bin is multilingual Arabic-capable."""
    model = root / "lib" / "src" / "whisper_model.dart"
    if not model.is_file():
        raise RuntimeError(f"Whisper model metadata source not found: {model}")
    source = model.read_text(encoding="utf-8")
    replacements = (
        ("WhisperModel.base => 149544538,", "WhisperModel.base => 147951465,"),
        ("WhisperModel.base => '143 MB',", "WhisperModel.base => '148 MB',"),
        ("/// ~75 MB, English-only, fast with balanced accuracy (~250 MB RAM required).",
         "/// ~148 MB, multilingual, fast with balanced accuracy (~250 MB RAM required)."),
        ("this != WhisperModel.tiny && this != WhisperModel.base;",
         "this != WhisperModel.tiny;"),
    )
    changed = False
    for old, new in replacements:
        if old in source:
            source = source.replace(old, new, 1)
            changed = True
        elif new not in source:
            raise RuntimeError(f"Unexpected flutter_whisper model metadata; missing expected declaration: {old}")
    if changed:
        model.write_text(source, encoding="utf-8")
        print(f"Patched {model}: pin exact multilingual Base metadata (147,951,465 bytes).")
    return changed


def patch_flutter_316_widget(root: Path) -> bool:
    """Patch only the optional upstream demo widget for Flutter 3.16 tests."""
    widget = root / "lib" / "src" / "widgets" / "transcription_view.dart"
    if not widget.is_file():
        raise RuntimeError(f"Whisper widget source not found: {widget}")
    widget_source = widget.read_text(encoding="utf-8")
    incompatible_count = widget_source.count("surfaceContainerHighest")
    if incompatible_count:
        widget_source = widget_source.replace("surfaceContainerHighest", "surfaceVariant")
        widget.write_text(widget_source, encoding="utf-8", newline="\n")
        print(f"Patched {widget}: Flutter 3.16-compatible ColorScheme property.")
        return True
    if "surfaceVariant" not in widget_source:
        raise RuntimeError("Unexpected flutter_whisper widget source: ColorScheme compatibility target not found.")
    return False


def main() -> int:
    root = package_root(Path.cwd())
    if "--compat-only" in sys.argv[1:]:
        patch_flutter_316_widget(root)
        return 0

    prepare_native_engine(root)
    patch_whisper_model_metadata(root)
    patch_whisper_context_libraries(root)
    patch_plugin_native_diagnostics(root)
    native = root / "android" / "src" / "main" / "cpp" / "whisper_jni.cpp"
    if not native.is_file():
        raise RuntimeError(f"Whisper JNI source not found: {native}")
    original = native.read_text(encoding="utf-8")
    patched = patch_source(original)
    patched = patch_jni_symbol_mangling(patched)
    if patched != original:
        native.write_text(patched, encoding="utf-8", newline="\n")
        print(f"Patched {native}: strict 16 kHz mono PCM16 WAV decoder installed.")
    else:
        print(f"Already patched: {native}")

    patch_flutter_316_widget(root)
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Whisper native patch failed: {error}", file=sys.stderr)
        raise SystemExit(1)
