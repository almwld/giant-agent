# Giant Agent AI Gateway

Node.js 20.3+ gateway. The gateway supports server-managed provider credentials or optional bring-your-own-key (BYOK). In BYOK mode, Flutter stores the provider key in Android secure storage and sends it to the user's HTTPS gateway per request; the gateway uses it in memory and does not persist it.

## Supported providers
- **OpenRouter (recommended starting point):** `AI_PROVIDER=openrouter`, `AI_MODEL=openrouter/free`. OpenRouter can automatically route to an available free model. Free variants are rate-limited (currently 20 requests/minute and 50/day on the free account tier); provider availability and quotas can change. This is useful for development, not a guaranteed production service.
- **Google Gemini API:** `AI_PROVIDER=gemini`, set `AI_API_KEY` to a Google AI Studio key, and choose a model enabled for that project. Google lists a no-cost tier for selected models, with usage limits and data-use terms that differ from paid service.
- **OpenAI API:** `AI_PROVIDER=openai`, set `AI_API_KEY` and a model enabled for the API project. API billing is separate from ChatGPT subscriptions.

OpenRouter and Gemini use their OpenAI-compatible Chat Completions streaming endpoints. OpenAI requests use the Responses API with semantic text-delta events and `store: false`. The gateway normalizes both streams to one mobile SSE contract. Provider credentials may come from server environment variables or the per-request `x-provider-api-key` header. Per-request keys are not written to disk.

## Local run
```sh
cp .env.example .env
# Edit .env, then export it into this shell; never commit the real .env.
set -a; . ./.env; set +a
npm test
npm start
```
Android emulator URL: `http://10.0.2.2:8080`. For production use an HTTPS URL. The app rejects insecure non-local gateway URLs.

For production, configure `GATEWAY_JWT_SECRET` (at least 32 random bytes), `GATEWAY_JWT_ISSUER`, and `GATEWAY_JWT_AUDIENCE`. Your trusted authentication service must issue short-lived HS256 JWTs containing `sub`, `iss`, `aud`, and `exp`; the gateway verifies the signature and claims and applies request limits per authenticated subject. Do not expose the JWT signing secret to the app. Static `APP_GATEWAY_TOKEN` authentication is accepted only outside production as a single-user development fallback. In Giant Agent → إعداد الذكاء الاصطناعي, enter the gateway URL, a valid user access token, and provider; optionally enter a BYOK provider key, or leave it empty to use the server-managed key. In BYOK mode, the provider key is stored in Android secure storage and sent to the gateway over HTTPS per request; it is not persisted by the gateway. The app uses `GET /v1/models` for credential verification and model discovery. The in-memory rate limiter is per subject but resets on restart; production still needs persistent quotas, account-level billing controls, abuse monitoring, and a real identity-provider integration before public launch.

## Deploy
Build this directory as a container using its Dockerfile. Deploy to Cloud Run or another Node container host, expose port 8080, and inject `GATEWAY_JWT_SECRET`, `GATEWAY_JWT_ISSUER`, `GATEWAY_JWT_AUDIENCE`, and the server-managed `AI_API_KEY` through the host's secret manager. Set `NODE_ENV=production`, `AI_PROVIDER`, `AI_MODEL`, and `ALLOWED_MODELS`. The app needs the HTTPS service URL.

## API
- `GET /health`
- `POST /v1/chat/stream` with a short-lived Bearer user JWT (production) or the development-only token. Body: `input`, optional `model`, optional base64 attachments. SSE output uses `data: {"type":"delta","delta":"..."}` and `data: [DONE]`.

Limits: 80 messages, 8 attachments, 14 MB encoded attachments, 30 requests/minute per authenticated subject across chat and model discovery (in-memory; resets on restart; bounded to 10,000 active subject windows by default). Images JPEG/PNG/WebP/GIF and text/JSON are accepted; unsupported binary formats fail explicitly. Before a public multi-user launch, add per-user identity, persistent quotas, abuse monitoring, and stronger billing controls.
