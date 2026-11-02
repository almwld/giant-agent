# Giant Agent AI Gateway

Node.js 20.3+ gateway. Provider credentials stay on the server; the Flutter app stores only a separate gateway access token using Android secure storage.

## Supported providers
- **OpenRouter (recommended starting point):** `AI_PROVIDER=openrouter`, `AI_MODEL=openrouter/free`. OpenRouter can automatically route to an available free model. Free variants are rate-limited (currently 20 requests/minute and 50/day on the free account tier); provider availability and quotas can change. This is useful for development, not a guaranteed production service.
- **Google Gemini API:** `AI_PROVIDER=gemini`, set `AI_API_KEY` to a Google AI Studio key, and choose a model enabled for that project. Google lists a no-cost tier for selected models, with usage limits and data-use terms that differ from paid service.
- **OpenAI API:** `AI_PROVIDER=openai`, set `AI_API_KEY` and a model enabled for the API project. API billing is separate from ChatGPT subscriptions.

OpenRouter and Gemini use their OpenAI-compatible Chat Completions streaming endpoints. OpenAI requests use the Responses API with semantic text-delta events and `store: false`. The gateway normalizes both streams to one mobile SSE contract. Provider credentials exist only in server environment variables.

## Local run
```sh
cp .env.example .env
# Edit .env, then export it into this shell; never commit the real .env.
set -a; . ./.env; set +a
npm test
npm start
```
Android emulator URL: `http://10.0.2.2:8080`. For production use an HTTPS URL. The app rejects insecure non-local gateway URLs.

Generate a gateway token with `openssl rand -hex 32`; set it as `APP_GATEWAY_TOKEN` on the server and enter the same value in Giant Agent → connection settings. This is a gateway access secret, not the provider API key. Rotate it if exposed.

## Deploy
Build this directory as a container using its Dockerfile. Deploy to Cloud Run or another Node container host, expose port 8080, and inject `APP_GATEWAY_TOKEN` and `AI_API_KEY` through the host's secret manager. Set `AI_PROVIDER`, `AI_MODEL`, and `ALLOWED_MODELS`. The app needs the HTTPS service URL.

## API
- `GET /health`
- `POST /v1/chat/stream` with Bearer gateway token. Body: `input`, optional `model`, optional base64 attachments. SSE output uses `data: {"type":"delta","delta":"..."}` and `data: [DONE]`.

Limits: 80 messages, 8 attachments, 14 MB encoded attachments, 30 requests/minute/IP. Images JPEG/PNG/WebP/GIF and text/JSON are accepted; unsupported binary formats fail explicitly. Before a public multi-user launch, add per-user identity, persistent quotas, abuse monitoring, and stronger billing controls.
