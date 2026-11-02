import test from 'node:test';
import assert from 'node:assert/strict';
import { validateInput, rateAllowed } from '../src/server.mjs';

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
