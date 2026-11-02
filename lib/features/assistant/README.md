# Giant Agent Assistant Core

This is an additive conversation and provider foundation. It does not replace the
existing welcome/chat route until the UI migration is reviewed separately.

## Runtime configuration

Configure the application gateway URL at build time:

```sh
flutter run --dart-define=GIANT_AGENT_GATEWAY_URL=https://your-api.example.com
```

The gateway must authenticate the signed-in app user and keep all model-provider
credentials server-side. The mobile app accepts only an application access token
through `AccessTokenProvider`; never add an OpenAI API key to Dart source,
assets, Gradle properties, or `--dart-define`.

## Streaming contract

The gateway endpoint is `POST /v1/chat/stream`, authenticated with the app
user's bearer token, and responds as Server-Sent Events. Each data frame is a
JSON object such as:

```json
{"type":"delta","delta":"Generated text"}
{"type":"error","message":"A safe user-facing error"}
```

The gateway may send `data: [DONE]` to end the stream. The backend should
validate user access, enforce quotas and attachment limits, map the request to
the selected provider, and never trust a client-supplied user identifier.

## Persistence

The assistant core uses a separate SQLite database
(`giant_agent_assistant.db`) with conversation-scoped messages and foreign-key
cascades. Existing application databases and the current chat screen are left
untouched. Future schema changes must use additive, versioned migrations.

## Local inference

`LocalAiProvider` is an adapter boundary, not a fake runtime. A concrete
`LocalInferenceEngine` must implement a compatible tokenizer, model-specific
tensor contract, decoding, cancellation and resource management before it is
registered as a working local provider.
