#!/usr/bin/env python3
"""Fetch pinned offline speech models during CI, verify, and stage as APK assets."""
import hashlib
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "voice_models"
ARTIFACTS = [
    ('ggml-base.bin',
     'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin',
     147951465,
     '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe'),
    ('nabra-82m-arabic-int8.tar.bz2',
     'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/nabra-82m-arabic-int8.tar.bz2',
     None,
     'a8608a504b1db4dd538b821409fe50b2d5cf37650c0a8753fa215bd6445e9964'),
]

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, url, expected_size, expected_hash in ARTIFACTS:
        target = OUT / name
        temporary = target.with_suffix(target.suffix + '.part')
        digest = hashlib.sha256()
        size = 0
        request = urllib.request.Request(url, headers={'User-Agent': 'GiantAgent-CI/1.0'})
        print('Downloading pinned model: ' + name, flush=True)
        with urllib.request.urlopen(request, timeout=120) as response, temporary.open('wb') as stream:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                stream.write(chunk)
                digest.update(chunk)
                size += len(chunk)
        if expected_size is not None and size != expected_size:
            temporary.unlink(missing_ok=True)
            raise RuntimeError(name + ': expected ' + str(expected_size) + ' bytes, got ' + str(size))
        if digest.hexdigest() != expected_hash:
            temporary.unlink(missing_ok=True)
            raise RuntimeError(name + ': SHA-256 mismatch: ' + digest.hexdigest())
        temporary.replace(target)
        print('VERIFIED ' + name + ': ' + str(size) + ' bytes', flush=True)
    print('BUNDLED_VOICE_MODELS_READY')

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('VOICE_MODEL_PREPARATION_FAILED: ' + str(error), file=sys.stderr)
        raise
