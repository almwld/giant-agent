import importlib.util
import unittest
from pathlib import Path

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
