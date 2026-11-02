import test from 'node:test';
import assert from 'node:assert/strict';
import { validateInput, rateAllowed, toResponsesInput } from '../src/server.mjs';

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

test('rejects models outside an explicit allowlist', () => { process.env.ALLOWED_MODELS = 'allowed/model'; assert.throws(() => validateInput({model:'blocked/model',input:[{role:'user',content:'x'}]}), /not enabled/); delete process.env.ALLOWED_MODELS; });
