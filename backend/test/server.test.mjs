import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

process.env.GATEWAY_JWT_SECRET = 'test-only-secret-with-at-least-32-characters';
process.env.GATEWAY_JWT_ISSUER = 'giant-agent-tests';
process.env.GATEWAY_JWT_AUDIENCE = 'giant-agent-mobile';
process.env.APP_GATEWAY_TOKEN = 'development-test-token-only';
process.env.MAX_RATE_LIMIT_ENTRIES = '3';

const { validateInput, rateAllowed, toResponsesInput, authenticate } =
  await import('../src/server.mjs');

function makeJwt(claimOverrides = {}, secret = process.env.GATEWAY_JWT_SECRET) {
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const header = encode({ alg: 'HS256', typ: 'JWT' });
  const payload = encode({
    sub: 'user-123',
    iss: process.env.GATEWAY_JWT_ISSUER,
    aud: process.env.GATEWAY_JWT_AUDIENCE,
    exp: Math.floor(Date.now() / 1000) + 300,
    ...claimOverrides,
  });
  const unsigned = header + '.' + payload;
  const signature = crypto.createHmac('sha256', secret).update(unsigned).digest('base64url');
  return unsigned + '.' + signature;
}

test('accepts a valid conversation request', () => {
  const result = validateInput({
    model: process.env.AI_MODEL || 'openrouter/free',
    input: [{ role: 'user', content: 'Hello' }],
    attachments: [],
  });
  assert.equal(result.messages.length, 1);
});

test('rejects invalid roles', () => {
  assert.throws(() => validateInput({ input: [{ role: 'admin', content: 'No' }] }), /Invalid message format/);
});

test('rejects empty input', () => {
  assert.throws(() => validateInput({ input: [] }), /between 1 and 80/);
});

test('rate limiter permits first request in a fresh window', () => {
  assert.equal(rateAllowed(`test-${Date.now()}-${Math.random()}`), true);
});

test('converts messages and image attachments to Responses API input parts', () => {
  const input = toResponsesInput([
    { role: 'user', content: [
      { type: 'text', text: 'Describe this' },
      { type: 'image_url', image_url: { url: 'data:image/png;base64,AA==' } },
    ] },
  ]);
  assert.equal(input[0].content[0].type, 'input_text');
  assert.equal(input[0].content[1].type, 'input_image');
});


test('authenticates a valid signed user token and returns its subject', () => {
  const principal = authenticate({ headers: { authorization: 'Bearer ' + makeJwt() } });
  assert.deepEqual(principal, { subject: 'user-123', method: 'jwt' });
});

test('rejects expired signed user tokens', () => {
  const token = makeJwt({ exp: Math.floor(Date.now() / 1000) - 1 });
  assert.equal(authenticate({ headers: { authorization: 'Bearer ' + token } }), null);
});

test('rejects tokens signed with an untrusted secret', () => {
  const token = makeJwt({}, 'attacker-controlled-secret-that-is-long-enough');
  assert.equal(authenticate({ headers: { authorization: 'Bearer ' + token } }), null);
});

test('rejects tokens without a subject or trusted issuer/audience', () => {
  const noSubject = makeJwt({ sub: '' });
  const wrongIssuer = makeJwt({ iss: 'untrusted-issuer' });
  const wrongAudience = makeJwt({ aud: 'other-client' });
  for (const token of [noSubject, wrongIssuer, wrongAudience]) {
    assert.equal(authenticate({ headers: { authorization: 'Bearer ' + token } }), null);
  }
});

test('allows the static shared token only outside production', () => {
  const request = { headers: { authorization: 'Bearer development-test-token-only' } };
  process.env.NODE_ENV = 'development';
  assert.deepEqual(authenticate(request), {
    subject: 'development-single-user',
    method: 'development-token',
  });
  process.env.NODE_ENV = 'production';
  assert.equal(authenticate(request), null);
  delete process.env.NODE_ENV;
});


test('rate limiter rejects requests after the configured window limit and resets after expiry', () => {
  const key = 'rate-window-regression';
  for (let index = 0; index < 30; index += 1) {
    assert.equal(rateAllowed(key, 1_000), true);
  }
  assert.equal(rateAllowed(key, 1_000), false);
  assert.equal(rateAllowed(key, 61_001), true);
});


test('rate limiter evicts expired subjects when its bounded map reaches capacity', () => {
  assert.equal(rateAllowed('capacity-a', 2_000), true);
  assert.equal(rateAllowed('capacity-b', 2_000), false);
  assert.equal(rateAllowed('capacity-after-expiry', Date.now() + 61_000), true);
});
