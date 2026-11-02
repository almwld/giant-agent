# Giant Agent — ChatGPT-Class Product Roadmap

## Product direction

Evolve Giant Agent in place into a standalone AI assistant with its existing identity, while retaining local-model support as a first-class option. The product must not impersonate OpenAI or depend on private ChatGPT source code.

## Repository audit baseline (2026-11-02)

- Flutter application; current entry route is `main.dart -> WelcomeScreen -> ChatScreen`.
- The current chat calls `ModelService.processInput()`.
- `ModelService.processInput()` currently returns a simulated response after a delay; it does not perform model inference or call a cloud AI API.
- The repository contains TFLite runner implementations, but the current chat path does not use them. The runners assume fixed tensor dimensions and interpret numeric output as characters; this is not a general-purpose text-generation interface. A model-specific tokenizer and tensor contract are required.
- The chat screen stores all messages in one SQLite table without conversation identifiers. Its image flow sends the image filename as text rather than image bytes.
- The project has no verified OpenAI integration or backend proxy. API credentials must never be embedded in the Flutter application.
- The latest inspected GitHub Actions run is #92 (success); run #91 failed. The current workflow builds universal and split APKs, but its ARM artifact paths are mislabelled: both ARM upload steps point to the armeabi-v7a output.

## Architecture target

1. **Flutter presentation** — ChatGPT-inspired conversation screen, responsive composer, conversation drawer, message actions, markdown/code rendering, theme and localization.
2. **Conversation domain** — conversation/message entities, streaming state, retry/cancel, title generation, per-conversation history and search.
3. **Provider abstraction** — a common interface for OpenAI cloud models and supported local runtimes. Provider selection must be explicit and failures must never be presented as successful model output.
4. **Secure AI gateway** — a server-side service that owns provider credentials, authenticates app users, applies rate limits and usage controls, and forwards requests to the OpenAI Responses API. No OpenAI secret in APK, assets, remote config, or source control.
5. **Streaming** — gateway-to-app streaming with cancellation, reconnect/error handling and partial-response persistence.
6. **Files and vision** — upload actual bytes through a controlled pipeline; enforce MIME, size and access limits; send supported images/files to providers only after explicit user action.
7. **Voice** — separate speech input/output foundation first; realtime voice transport in a later phase, with microphone permission requested only when the user starts voice.
8. **Memory and tools** — user-controlled memory, searchable conversation history, and permission-gated tools with visible execution status.
9. **Local AI** — retain local inference as a separate provider. Support only runtimes and model formats with a verified tokenizer, tensor contract and licensing.

## Delivery phases

- **Phase 0 — Baseline and safety:** preserve the current app identity and main route; document existing defects; isolate work on a feature branch.
- **Phase 1 — Conversation foundation:** conversation IDs, durable message model, repository/service boundaries, robust send/retry/cancel and UI state.
- **Phase 2 — Cloud provider:** secure backend gateway, Responses API integration, streaming and model configuration.
- **Phase 3 — Chat experience:** markdown, code blocks, copy/share/regenerate, conversation search, attachment previews and responsive navigation.
- **Phase 4 — Multimodal:** image/file analysis and voice.
- **Phase 5 — Memory and tools:** opt-in memory, tool permissions, usage limits and auditability.
- **Phase 6 — Stabilization:** analyzer, unit/widget tests, Android build, artifact verification and release checks.

## Implementation status — 2026-11-03

The following status reflects code present on `feat/chatgpt-experience-foundation`; it is not a claim that a production service is deployed.

### Delivered in the current branch
- Conversation entities and a separate versioned SQLite store with per-conversation message history and search.
- A `ChatController` for streaming, cancellation, retry, and persisted assistant/user messages.
- The existing `ChatScreen` now uses the assistant controller while retaining the legacy message database for backwards compatibility; assistant messages support copy/share and retry after failure.
- Node gateway routes for streaming and model discovery, OpenAI Responses API support (`store: false`), OpenRouter/Gemini-compatible streaming, and bounded image/text attachments.
- Optional server-managed provider credentials or user BYOK credentials; the mobile UI no longer requires a provider key when the server has one configured.
- Signed HS256 JWT verification with subject, issuer, audience, expiry and not-before checks; mobile settings can detect expired JWTs before a request, and 401 responses explain session expiry. Chat and model discovery share per-subject in-memory request limits, with expired-window cleanup and a bounded active-subject map. Static shared-token auth is development-only and rejected in production.
- Strict ReAct JSON decisions, tool schema validation (including argument types), bounded execution, duplicate-action blocking, and regression coverage for protocol and tool failures.
- CI workflow for Flutter analysis/tests/debug APK and gateway syntax/unit tests. The last fully completed run before the newest commits passed analysis, tests, gateway checks and debug APK build.

### In progress / not yet production-ready
- **Identity integration:** JWT verification and client-side expiry detection exist, and the assistant factory now accepts an injected access-token provider so a future identity SDK can supply refreshed tokens without changing the gateway transport. No trusted issuer or app sign-in/refresh implementation is wired yet; the default path still reads a manually supplied token, and sign-out/session lifecycle remain.
- **Gateway operations:** request limiting now covers both chat and model discovery and bounds active in-memory limiter entries, but counters still reset on restart; no persistent per-account usage ledger, billing enforcement, abuse monitoring, key rotation workflow, or deployment has been verified.
- **Chat UX:** basic conversation drawer, composer, cancel, image/text attachment and history are present. Markdown/code rendering, regenerate controls, richer retry states, attachment previews, and full accessibility/localization remain.
- **Multimodal:** image and text attachment transport is implemented; binary document parsing, upload lifecycle/retention controls, voice input/output and realtime voice are not implemented.
- **Memory/tools:** no opt-in cross-conversation memory, approval UI, fine-grained tool permissions, or durable action audit log yet. Current built-in tools are calculator and device date/time only.
- **Local inference:** only the provider/engine abstraction exists. No GGUF, ONNX or TFLite generation runtime is registered or verified; importing a model file is not evidence of inference support.
- **Release validation:** latest commits are awaiting CI. No release APK/AAB, signed artifact, real-device inference test, or production gateway deployment is claimed.

### Next execution order
1. Complete CI on the latest branch head and fix any regressions.
2. Close the authentication loop: connect a real app identity provider, obtain/refresh user JWTs, and remove the manual long-lived token workflow.
3. Add persistent per-user quotas, usage accounting, request cancellation propagation, and security/audit events.
4. Finish chat interaction quality (Markdown/code, message actions, retry state, attachment previews, and conversation lifecycle tests).
5. Add consent-based memory and permission-gated tools with visible approvals and durable audit records.
6. Implement one concrete local runtime only after selecting a compatible model, tokenizer, decoding contract and Android integration; verify it on a physical device before exposing it as available.
7. Complete voice and broader multimodal support, then run release/artifact and device validation before production publication.

## Non-negotiable engineering rules

- Do not expose provider API keys in the mobile app.
- Do not fabricate model responses, tool results, citations, or successful uploads.
- Do not claim a local model is generative unless its tokenizer and inference contract are implemented and verified.
- Preserve existing Giant Agent identity and useful local-model features unless a replacement is demonstrably better.
- Keep each coherent change group in a separate commit.
- Fix CI failures caused by our changes before reporting completion.
- Do not change Android application ID, signing, Flutter/Gradle/NDK versions, or release workflow behavior without a verified need.
- Prefer additive migrations and preserve existing user conversation data.
