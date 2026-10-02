import assert from 'node:assert/strict';
import { test } from 'node:test';
import { transportError } from '../src/transport.ts';

test('network and CORS failures do not expose raw fetch errors', () => {
  for (const text of ['Failed to fetch', 'Load failed', 'NetworkError when attempting to fetch resource.']) {
    assert.match(transportError(new TypeError(text)).message, /layanan cloud/);
    assert.ok(!transportError(new TypeError(text)).message.includes(text));
  }
});

test('cancellation, timeout and application errors stay distinct', () => {
  assert.match(transportError(new DOMException('', 'AbortError')).message, /dibatalkan/);
  assert.match(transportError(new DOMException('', 'TimeoutError')).message, /Muat ulang/);
  const failure = new Error('Saldo tidak cukup.');
  assert.equal(transportError(failure), failure);
});
