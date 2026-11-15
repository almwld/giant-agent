import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class VoiceModelIntegrityTests(unittest.TestCase):
    def test_nabra_archive_digest_matches_runtime_documentation(self):
        service = (ROOT / "lib/services/local_arabic_tts_service.dart").read_text(encoding="utf-8")
        readme = (ROOT / "assets/voice_models/README.md").read_text(encoding="utf-8")
        runtime_digest = re.search(r"modelArchiveSha256\s*=\s*\n\s*'([0-9a-f]{64})'", service)
        documented_digest = re.search(r"Nabra Arabic TTS.*?SHA-256 `([0-9a-f]{64})`", readme)
        self.assertIsNotNone(runtime_digest, "Nabra runtime digest declaration is missing")
        self.assertIsNotNone(documented_digest, "Nabra documented digest is missing")
        self.assertEqual(runtime_digest.group(1), documented_digest.group(1))

    def test_voice_models_are_bundled_and_prepared_before_flutter_build(self):
        pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        script = (ROOT / "tool/prepare_voice_models.py").read_text(encoding="utf-8")
        asr = (ROOT / "lib/services/local_speech_recognition_service.dart").read_text(encoding="utf-8")
        tts = (ROOT / "lib/services/local_arabic_tts_service.dart").read_text(encoding="utf-8")
        self.assertIn("assets/voice_models/ggml-base.bin", pubspec)
        self.assertIn("assets/voice_models/nabra-82m-arabic-int8.tar.bz2", pubspec)
        self.assertIn("tool/prepare_voice_models.py", workflow)
        self.assertIn("rootBundle.load('assets/voice_models/ggml-base.bin')", asr)
        self.assertIn("rootBundle.load(", tts)
        self.assertNotIn("http.Request", asr)
        self.assertNotIn("http.Request", tts)
        self.assertIn("60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe", script)
        self.assertIn("a8608a504b1db4dd538b821409fe50b2d5cf37650c0a8753fa215bd6445e9964", script)

    def test_whisper_base_digest_and_size_match_runtime_documentation(self):
        service = (ROOT / "lib/services/local_speech_recognition_service.dart").read_text(encoding="utf-8")
        readme = (ROOT / "assets/voice_models/README.md").read_text(encoding="utf-8")
        runtime_size = re.search(r"_baseModelBytes\s*=\s*(\d+)", service)
        runtime_digest = re.search(r"_baseModelSha256\s*=\s*\n\s*'([0-9a-f]{64})'", service)
        documented_size = re.search(r"ggml-base\.bin`?\s*\(([\d,]+) bytes\)", readme)
        documented_digest = re.search(r"SHA-256 \x60([0-9a-f]{64})\x60", readme)
        self.assertIsNotNone(runtime_size, "Whisper Base exact byte count is missing")
        self.assertIsNotNone(runtime_digest, "Whisper Base SHA-256 is missing")
        self.assertIsNotNone(documented_size, "Whisper Base documented byte count is missing")
        self.assertIsNotNone(documented_digest, "Whisper Base documented SHA-256 is missing")
        self.assertEqual(runtime_size.group(1), documented_size.group(1).replace(',', ''))
        self.assertEqual(runtime_digest.group(1), documented_digest.group(1))
        self.assertLess(service.index("_ensureVerifiedBaseModel"), service.index("_whisper.initialize"))

    def test_whisper_model_is_not_loaded_from_flutter_assets(self):
        service = (ROOT / "lib/services/local_speech_recognition_service.dart").read_text(encoding="utf-8")
        self.assertNotIn("assets/voice_models/ggml-base.bin", service)
        self.assertNotIn("rootBundle.load", service)
        self.assertIn("_whisper.initialize", service)


if __name__ == "__main__":
    unittest.main()
