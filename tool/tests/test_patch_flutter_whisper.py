import importlib.util
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

MODULE_PATH = Path(__file__).resolve().parents[1] / "patch_flutter_whisper.py"
SPEC = importlib.util.spec_from_file_location("patch_flutter_whisper", MODULE_PATH)
PATCHER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(PATCHER)


class WhisperNativePatchTests(unittest.TestCase):
    def setUp(self):
        self.source = """#include <cstring>
#define MA_NO_DEVICE_IO
#define MA_NO_THREADING
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

// ---- audio decode:
static bool old_decoder() { return true; }
// ---- JSON helpers ----
static void parse_json() {}
"""


    def test_limits_native_inference_threads_to_available_cpu_cores(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            native = root / "android/src/main/cpp/whisper_jni.cpp"
            native.parent.mkdir(parents=True)
            native.write_text(
                '#include <cstring>\\n    params.n_threads = 4;\\n',
                encoding="utf-8",
            )
            self.assertTrue(PATCHER.patch_native_inference_threads(root))
            patched = native.read_text(encoding="utf-8")
            self.assertIn("std::thread::hardware_concurrency()", patched)
            self.assertIn("std::min(4u, cpu_count)", patched)
            self.assertIn("#include <algorithm>", patched)
            self.assertFalse(PATCHER.patch_native_inference_threads(root))
            self.assertEqual(native.read_text(encoding="utf-8"), patched)

    def test_adds_x86_64_to_native_plugin_abis(self):
        gradle = 'abiFilters "arm64-v8a", "armeabi-v7a"'
        patched = PATCHER.patch_android_abis(gradle)
        self.assertIn('"x86_64"', patched)
        self.assertEqual(PATCHER.patch_android_abis(patched), patched)

    def test_rejects_unrecognized_abi_filter_declaration(self):
        with self.assertRaisesRegex(RuntimeError, "ABI filter declaration not found"):
            PATCHER.patch_android_abis('abiFilters "arm64-v8a"')


    def test_patches_whisper_context_to_load_packaged_ggml_soname(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            context = root / "android/src/main/kotlin/io/github/govindtank/flutter_whisper/WhisperContext.kt"
            context.parent.mkdir(parents=True)
            context.write_text(
                'System.loadLibrary("ggml-cpu")\\nSystem.loadLibrary("whisper")\\n',
                encoding="utf-8",
            )
            cmake = root / "android/src/main/cpp/CMakeLists.txt"
            cmake.parent.mkdir(parents=True)
            cmake.write_text(
                'copy_if_different libggml-cpu.so libggml.so\\n'
                'set_target_properties(whisper_jni PROPERTIES OUTPUT_NAME whisper)',
                encoding="utf-8",
            )

            self.assertTrue(PATCHER.patch_whisper_context_libraries(root))
            patched = context.read_text(encoding="utf-8")
            self.assertIn('System.loadLibrary("ggml")', patched)
            self.assertIn('System.loadLibrary("whisper")', patched)
            self.assertIn('System.loadLibrary("whisper_jni")', patched)
            self.assertIn(
                'System.loadLibrary("whisper")' + chr(10) + '        System.loadLibrary("whisper_jni")',
                patched,
            )
            self.assertLess(
                patched.index('System.loadLibrary("whisper")'),
                patched.index('System.loadLibrary("whisper_jni")'),
            )
            self.assertNotIn('System.loadLibrary("ggml-cpu")', patched)
            cmake_patched = cmake.read_text(encoding="utf-8")
            self.assertIn('OUTPUT_NAME whisper_jni', cmake_patched)
            self.assertNotIn('OUTPUT_NAME whisper)', cmake_patched)
            self.assertFalse(PATCHER.patch_whisper_context_libraries(root))

    def test_rejects_unexpected_whisper_ggml_packaging_rule(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            context = root / "android/src/main/kotlin/io/github/govindtank/flutter_whisper/WhisperContext.kt"
            context.parent.mkdir(parents=True)
            context.write_text('System.loadLibrary("ggml-cpu")', encoding="utf-8")
            cmake = root / "android/src/main/cpp/CMakeLists.txt"
            cmake.parent.mkdir(parents=True)
            cmake.write_text("add_library(whisper)", encoding="utf-8")

            with self.assertRaisesRegex(RuntimeError, "packaging rule"):
                PATCHER.patch_whisper_context_libraries(root)



    def test_escapes_underscore_in_whisper_jni_package_symbols(self):
        old_prefix = "Java_io_github_govindtank_flutter_whisper_WhisperContext_"
        methods = ("nativeInit", "nativeTranscribe", "nativeCancel", "nativeFree")
        source = "\\n".join(old_prefix + method for method in methods)
        patched = PATCHER.patch_jni_symbol_mangling(source)
        new_prefix = "Java_io_github_govindtank_flutter_1whisper_WhisperContext_"
        for method in methods:
            self.assertIn(new_prefix + method, patched)
        self.assertNotIn(old_prefix, patched)
        self.assertEqual(PATCHER.patch_jni_symbol_mangling(patched), patched)

    def test_rejects_incomplete_whisper_jni_exports(self):
        with self.assertRaisesRegex(RuntimeError, "nativeTranscribe"):
            PATCHER.patch_jni_symbol_mangling(
                "Java_io_github_govindtank_flutter_1whisper_WhisperContext_nativeInit"
            )

    def test_corrects_multilingual_base_model_metadata(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            model = root / "lib/src/whisper_model.dart"
            model.parent.mkdir(parents=True)
            model.write_text(
                "WhisperModel.base => 149544538,\\n"
                "WhisperModel.base => '143 MB',\\n"
                "/// ~75 MB, English-only, fast with balanced accuracy (~250 MB RAM required).\\n"
                "this != WhisperModel.tiny && this != WhisperModel.base;\\n",
                encoding="utf-8",
            )
            self.assertTrue(PATCHER.patch_whisper_model_metadata(root))
            patched = model.read_text(encoding="utf-8")
            self.assertIn("WhisperModel.base => 147951465,", patched)
            self.assertIn("WhisperModel.base => '148 MB',", patched)
            self.assertIn("~148 MB, multilingual", patched)
            self.assertIn("this != WhisperModel.tiny;", patched)
            self.assertFalse(PATCHER.patch_whisper_model_metadata(root))

    def test_rejects_unrecognized_base_model_metadata(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            model = root / "lib/src/whisper_model.dart"
            model.parent.mkdir(parents=True)
            model.write_text("unrecognized model metadata", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "Unexpected flutter_whisper model metadata"):
                PATCHER.patch_whisper_model_metadata(root)


    def test_flutter_316_widget_patch_is_safe_and_idempotent(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            widget = root / "lib" / "src" / "widgets" / "transcription_view.dart"
            widget.parent.mkdir(parents=True)
            widget.write_text(
                "colorScheme.surfaceContainerHighest.withAlpha(80)",
                encoding="utf-8",
            )
            self.assertTrue(PATCHER.patch_flutter_316_widget(root))
            patched = widget.read_text(encoding="utf-8")
            self.assertIn("surfaceVariant", patched)
            self.assertNotIn("surfaceContainerHighest", patched)
            self.assertFalse(PATCHER.patch_flutter_316_widget(root))

    def test_flutter_316_widget_patch_rejects_missing_widget(self):
        with TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "Whisper widget source not found"):
                PATCHER.patch_flutter_316_widget(Path(directory))

    def test_replaces_entire_decoder_and_removes_miniaudio(self):
        patched = PATCHER.patch_source(self.source)
        self.assertIn(PATCHER.MARKER, patched)
        self.assertIn("load_audio_16k", patched)
        self.assertIn("#include <cstdint>", patched)
        self.assertIn("#include <fstream>", patched)
        self.assertIn("// ---- JSON helpers ----", patched)
        self.assertNotIn("miniaudio.h", patched)
        self.assertNotIn("MINIAUDIO_IMPLEMENTATION", patched)
        self.assertNotIn("old_decoder", patched)

    def test_patch_is_idempotent(self):
        once = PATCHER.patch_source(self.source)
        self.assertEqual(PATCHER.patch_source(once), once)

    def test_rejects_unexpected_upstream_include_block(self):
        with self.assertRaisesRegex(RuntimeError, "include block not found"):
            PATCHER.patch_source(self.source.replace(PATCHER.MINIAUDIO_BLOCK, ""))

    def test_rejects_unexpected_decoder_boundaries(self):
        malformed = self.source.replace("// ---- JSON helpers ----", "// JSON helpers")
        with self.assertRaisesRegex(RuntimeError, "section boundaries not found"):
            PATCHER.patch_source(malformed)


if __name__ == "__main__":
    unittest.main()
