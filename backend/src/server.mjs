import http from 'node:http';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

const PORT = Number(process.env.PORT || 8080);
const APP_TOKEN = process.env.APP_GATEWAY_TOKEN || '';
const PROVIDER = (process.env.AI_PROVIDER || 'openrouter').toLowerCase();
const API_KEY = process.env.AI_API_KEY || '';
const BASE_URL = (process.env.AI_BASE_URL || defaultBaseUrl(PROVIDER)).replace(/\/+$/, '');
const DEFAULT_MODEL = process.env.AI_MODEL || (PROVIDER === 'openrouter' ? 'openrouter/free' : PROVIDER === 'gemini' ? 'gemini-3.8-flash' : 'gpt-4.1-mini');
const ALLOWED_MODELS = (process.env.ALLOWED_MODELS || DEFAULT_MODEL).split(',').map(v => v.trim()).filter(Boolean);
const MAX_BODY = Number(process.env.MAX_BODY_BYTES || 18 * 1024 * 1024);
const RATE_LIMIT = Number(process.env.RATE_LIMIT_PER_MINUTE || 30);
const windows = new Map();

function defaultBaseUrl(provider) {
  if (provider === 'openrouter') return 'https://openrouter.ai/api/v1';
  if (provider === 'gemini') return 'https://generativelanguage.googleapis.com/v1beta/openai';
  return 'https://api.openai.com/v1';
}
function json(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
}
function secureEqual(a, b) {
  const left = Buffer.from(a), right = Buffer.from(b);
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}
function authorized(req) {
  const header = req.headers.authorization || '';
  return Boolean(APP_TOKEN && header.startsWith('Bearer ') && secureEqual(header.slice(7), APP_TOKEN));
}
function rateAllowed(key) {
  const now = Date.now(), entry = windows.get(key);
  if (!entry || now - entry.start >= 60_000) {
    windows.set(key, { start: now, count: 1 });
    return true;
  }
  entry.count += 1;
  return entry.count <= RATE_LIMIT;
}
async function readJson(req) {
  const chunks = []; let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY) throw Object.assign(new Error('Request body too large'), { status: 413 });
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw Object.assign(new Error('Invalid JSON body'), { status: 400 }); }
}
function validateInput(body) {
  if (!body || !Array.isArray(body.input) || body.input.length === 0 || body.input.length > 80)
    throw Object.assign(new Error('input must contain between 1 and 80 messages'), { status: 400 });
  const messages = body.input.map(item => {
    if (!item || !['user', 'assistant', 'system'].includes(item.role) ||
        typeof item.content !== 'string' || item.content.length > 100_000)
      throw Object.assign(new Error('Invalid message format'), { status: 400 });
    return { role: item.role, content: item.content };
  });
  const model = typeof body.model === 'string' && body.model.trim() ? body.model.trim() : DEFAULT_MODEL;
  if (!ALLOWED_MODELS.includes('*') && !ALLOWED_MODELS.includes(model))
    throw Object.assign(new Error('Requested model is not enabled on this gateway'), { status: 403 });
  const attachments = Array.isArray(body.attachments) ? body.attachments : [];
  if (attachments.length > 8) throw Object.assign(new Error('Maximum 8 attachments'), { status: 400 });
  let total = 0;
  for (const file of attachments) {
    if (!file || typeof file.data_base64 !== 'string' || typeof file.mime_type !== 'string')
      throw Object.assign(new Error('Invalid attachment'), { status: 400 });
    total += Buffer.byteLength(file.data_base64, 'utf8');
    if (total > 14 * 1024 * 1024) throw Object.assign(new Error('Attachments exceed size limit'), { status: 413 });
  }
  return { messages, model, attachments };
}
function attachContent(messages, attachments) {
  if (!attachments.length) return messages;
  const images = [], extracted = [];
  for (const file of attachments) {
    const bytes = Buffer.from(file.data_base64, 'base64');
    if (file.mime_type.startsWith('image/')) {
      if (!['image/jpeg', 'image/png', 'image/webp', 'image/gif'].includes(file.mime_type))
        throw Object.assign(new Error('Unsupported image format'), { status: 415 });
      images.push({ type: 'image_url', image_url: { url: `data:${file.mime_type};base64,${bytes.toString('base64')}` } });
    } else if (file.mime_type.startsWith('text/') || file.mime_type === 'application/json') {
      if (bytes.length > 1_000_000) throw Object.assign(new Error('Text attachment exceeds 1 MB'), { status: 413 });
      extracted.push(`\n\n[Attachment: ${String(file.name || 'file').slice(0, 120)}]\n${bytes.toString('utf8')}`);
    } else {
      throw Object.assign(new Error('This gateway currently accepts images and text files only'), { status: 415 });
    }
  }
  const lastUser = messages.findLastIndex(m => m.role === 'user');
  if (lastUser < 0) throw Object.assign(new Error('At least one user message is required'), { status: 400 });
  const current = messages[lastUser];
  messages[lastUser] = { role: 'user', content: [
    { type: 'text', text: current.content + extracted.join('') }, ...images,
  ] };
  return messages;
}
async function streamChat(req, res) {
  if (!API_KEY) return json(res, 503, { error: 'AI provider is not configured on the server' });
  const { messages, model, attachments } = validateInput(await readJson(req));
  const upstreamMessages = attachContent(messages, attachments);
  const headers = { 'content-type': 'application/json', authorization: `Bearer ${API_KEY}` };
  if (PROVIDER === 'openrouter') {
    headers['HTTP-Referer'] = process.env.APP_PUBLIC_URL || 'https://github.com/almwld/giant-agent';
    headers['X-Title'] = 'Giant Agent';
  }
  const abort = new AbortController();
  req.on('aborted', () => abort.abort());
  const upstream = await fetch(`${BASE_URL}/chat/completions`, {
    method: 'POST', headers,
    body: JSON.stringify({ model, messages: upstreamMessages, stream: true, temperature: 0.7, max_tokens: 4096 }),
    signal: AbortSignal.any([AbortSignal.timeout(180_000), abort.signal]),
  });
  if (!upstream.ok) {
    const detail = (await upstream.text()).slice(0, 2000);
    return json(res, upstream.status >= 500 ? 502 : upstream.status, {
      error: 'AI provider rejected the request', provider_status: upstream.status, detail,
    });
  }
  res.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache, no-transform',
    connection: 'keep-alive',
    'x-accel-buffering': 'no',
  });
  const reader = upstream.body.getReader(), decoder = new TextDecoder();
  let buffer = '';
  res.on('close', () => { if (!res.writableEnded) abort.abort(); });
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n'); buffer = lines.pop() || '';
      for (const line of lines) {
        if (!line.startsWith('data:')) continue;
        const data = line.slice(5).trim();
        if (!data || data === '[DONE]') continue;
        let event; try { event = JSON.parse(data); } catch { continue; }
        const delta = event.choices?.[0]?.delta?.content;
        if (typeof delta === 'string' && delta.length)
          res.write(`data: ${JSON.stringify({ type: 'delta', delta })}\n\n`);
        else if (Array.isArray(delta)) for (const part of delta)
          if (part.type === 'text' && typeof part.text === 'string')
            res.write(`data: ${JSON.stringify({ type: 'delta', delta: part.text })}\n\n`);
      }
    }
    res.write('data: [DONE]\n\n');
  } catch (error) {
    if (!res.destroyed) res.write(`data: ${JSON.stringify({ type: 'error', message: error.message || 'Upstream stream interrupted' })}\n\n`);
  } finally {
    reader.releaseLock();
    if (!res.destroyed) res.end();
  }
}
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
  if (req.method === 'GET' && url.pathname === '/health')
    return json(res, 200, { ok: true, provider: PROVIDER, model: DEFAULT_MODEL, configured: Boolean(APP_TOKEN && API_KEY) });
  if (req.method !== 'POST' || url.pathname !== '/v1/chat/stream')
    return json(res, 404, { error: 'Not found' });
  const ip = req.headers['x-forwarded-for']?.split(',')[0]?.trim() || req.socket.remoteAddress || 'unknown';
  if (!rateAllowed(ip)) return json(res, 429, { error: 'Rate limit exceeded. Try again shortly.' });
  if (!authorized(req)) return json(res, 401, { error: 'Unauthorized gateway token' });
  try {
    await streamChat(req, res);
  } catch (error) {
    if (!res.headersSent) json(res, error.status || 500, { error: error.status ? error.message : 'Gateway request failed' });
    else if (!res.destroyed) {
      res.write(`data: ${JSON.stringify({ type: 'error', message: 'Gateway stream failed' })}\n\n`);
      res.end();
    }
  }
});
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  server.listen(PORT, '0.0.0.0', () =>
    console.log(`Giant Agent AI gateway listening on :${PORT}; provider=${PROVIDER}; model=${DEFAULT_MODEL}`));
}
export { server, validateInput, rateAllowed };
