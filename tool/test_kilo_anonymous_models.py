#!/usr/bin/env python3
"""Anonymous live smoke test for Kilo free models. No credentials are read or sent."""
import json
import sys
import time
import urllib.error
import urllib.request

BASE = "https://ai-gateway.kilo.ai/api/v1"
MODEL_IDS = [
    "kilo-auto/free",
    "baidu/ernie-5.5-flash-preview:free",
    "cohere/north-mini-code:free",
    "dots-studio/dots-3-note-preview:free",
    "liquid/lfm-3-1.7b:free",
    "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",
    "nvidia/nemotron-3-ultra-550b-a55b:free",
    "nvidia/nemotron-3.5-lightning:free",
    "nvidia/nemotron-3.5-super-vl:free",
    "openrouter/free",
    "particle-ai/particle-1:free",
    "reflection/beam-free",
    "stealth/glyph-cluster",
]

def request_json(url, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    headers = {"Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method="GET" if data is None else "POST")
    with urllib.request.urlopen(req, timeout=45) as response:
        return response.status, json.loads(response.read().decode("utf-8"))

def is_free(model):
    pricing = model.get("pricing") or {}
    try:
        return float(pricing.get("prompt", "nan")) == 0 and float(pricing.get("completion", "nan")) == 0
    except (TypeError, ValueError):
        return False

def main():
    status, catalog = request_json(BASE + "/models")
    entries = catalog.get("data", []) if isinstance(catalog, dict) else []
    by_id = {item.get("id"): item for item in entries if isinstance(item, dict)}
    print(f"Anonymous catalog: HTTP {status}; {len(by_id)} models listed; Authorization header: absent")
    passed, skipped, failed = 0, 0, 0
    for model_id in MODEL_IDS:
        item = by_id.get(model_id)
        if item is None:
            print(f"NOT LISTED  {model_id}")
            skipped += 1
            continue
        if not is_free(item):
            print(f"NOT FREE    {model_id}")
            skipped += 1
            continue
        payload = {
            "model": model_id,
            "messages": [{"role": "user", "content": "Reply with exactly OK."}],
            "max_tokens": 8,
            "temperature": 0,
        }
        try:
            code, result = request_json(BASE + "/chat/completions", payload)
            choices = result.get("choices") or []
            message = choices[0].get("message", {}) if choices else {}
            content = message.get("content") if isinstance(message, dict) else None
            if isinstance(content, list):
                content = " ".join(
                    part.get("text", "") for part in content if isinstance(part, dict)
                )
            if not isinstance(content, str) or not content.strip():
                content = next(
                    (message.get(key) for key in ("reasoning_content", "reasoning", "output_text")
                     if isinstance(message, dict) and isinstance(message.get(key), str)
                     and message.get(key).strip()),
                    None,
                )
            if code == 200 and isinstance(content, str) and content.strip():
                print(f"PASS        {model_id}")
                passed += 1
            else:
                preview = json.dumps(result, ensure_ascii=False)[:500]
                print(f"FAIL        {model_id}: HTTP {code}, response={preview}")
                failed += 1
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")[:240]
            print(f"FAIL        {model_id}: HTTP {exc.code}: {detail}")
            failed += 1
        except Exception as exc:
            print(f"FAIL        {model_id}: {type(exc).__name__}: {exc}")
            failed += 1
        time.sleep(0.25)
    print(f"SUMMARY     passed={passed}, unavailable_or_not_free={skipped}, failed={failed}")
    if passed == 0:
        print("ERROR: No requested model completed an anonymous live inference request.")
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
