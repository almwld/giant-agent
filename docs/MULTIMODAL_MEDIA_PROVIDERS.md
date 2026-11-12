# Giant Agent — Multimodal media provider contract

Giant Agent keeps text inference and media inference as separate capabilities.
The shared ModelService/AgentKernel remains the orchestration layer; image and
video providers are registered through MediaProviderRegistry.

## Supported capabilities

- generateImage
- editImage
- generateVideo
- editVideo

## Provider adapter requirements

Implement MediaProviderAdapter for each model/vendor and register it during
application initialization. Each adapter must declare only capabilities that
the upstream model/API actually supports.

The adapter owns provider-specific behavior:

- authentication and secure credential lookup;
- JSON or multipart upload for image editing;
- asynchronous job creation and polling for video generation/editing;
- timeout, cancellation, rate-limit and provider error mapping;
- downloading generated assets into app-private storage;
- returning MIME types, local paths and provider metadata.

Do not route media requests through a text-only chat completion endpoint.
Do not claim a video job is complete until the provider returns a completed
state and a downloadable video asset. Keep provider API keys in
FlutterSecureStorage; never place secrets in prompts, logs, or chat history.

## UI integration contract

The chat composer should expose only actions for which at least one registered
provider reports support. Editing actions must request a source asset. Results
must be persisted as media attachments in the current conversation and shown
with the appropriate image/video renderer.

## Current status

This is the provider boundary and capability registry only. No image/video
vendor is configured in this commit, so generation and editing are not yet
advertised as available. Add a concrete adapter when the target model API and
authentication scheme are selected.
