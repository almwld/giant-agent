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

## Non-negotiable engineering rules

- Do not expose provider API keys in the mobile app.
- Do not fabricate model responses, tool results, citations, or successful uploads.
- Do not claim a local model is generative unless its tokenizer and inference contract are implemented and verified.
- Preserve existing Giant Agent identity and useful local-model features unless a replacement is demonstrably better.
- Keep each coherent change group in a separate commit.
- Fix CI failures caused by our changes before reporting completion.
- Do not change Android application ID, signing, Flutter/Gradle/NDK versions, or release workflow behavior without a verified need.
- Prefer additive migrations and preserve existing user conversation data.
