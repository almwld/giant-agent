import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class VoiceModelIntegrityTests(unittest.TestCase):
    def test_nabra_archive_digest_matches_build_and_runtime(self):
        gradle = (ROOT / "android/app/build.gradle").read_text(encoding="utf-8")
        service = (
            ROOT / "lib/services/local_arabic_tts_service.dart"
        ).read_text(encoding="utf-8")

        archive_block = re.search(
            r'downloadPinned\\(\\s*"https://github\\.com/k2-fsa/sherpa-onnx/releases/download/tts-models/nabra-82m-arabic-int8\\.tar\\.bz2",\\s*'
            r'new File\\(bundledVoiceModelDir, "nabra-82m-arabic-int8\\.tar\\.bz2"\\),\\s*'
            r'"([0-9a-f]{64})"',
            gradle,
        )
        runtime_digest = re.search(
            r'modelArchiveSha256\\s*=\\s*\\n\\s*\'([0-9a-f]{64})\'',
            service,
        )

        self.assertIsNotNone(archive_block, "Nabra build digest declaration is missing")
        self.assertIsNotNone(runtime_digest, "Nabra runtime digest declaration is missing")
        self.assertEqual(
            archive_block.group(1),
            runtime_digest.group(1),
            "Nabra archive digest differs between Gradle provisioning and runtime extraction",
        )


if __name__ == "__main__":
    unittest.main()
