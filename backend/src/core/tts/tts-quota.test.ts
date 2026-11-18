import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { allowedVoiceIds, TtsQuota } from './tts-quota.js';

describe('TtsQuota', () => {
  it('corta al pasar el tope diario por usuario', () => {
    const quota = new TtsQuota(1000, () => new Date('2026-11-17T10:00:00Z'));
    assert.equal(quota.tryConsume('a', 600), true);
    assert.equal(quota.tryConsume('a', 500), false);
    assert.equal(quota.tryConsume('a', 400), true);
    // Otro usuario tiene su propia cuota.
    assert.equal(quota.tryConsume('b', 1000), true);
  });

  it('se reinicia al cambiar el día UTC', () => {
    let now = new Date('2026-11-17T23:59:00Z');
    const quota = new TtsQuota(100, () => now);
    assert.equal(quota.tryConsume('a', 100), true);
    assert.equal(quota.tryConsume('a', 1), false);
    now = new Date('2026-11-18T00:00:01Z');
    assert.equal(quota.tryConsume('a', 100), true);
  });

  it('devuelve lo reservado si la síntesis falla', () => {
    const quota = new TtsQuota(100, () => new Date('2026-11-17T10:00:00Z'));
    assert.equal(quota.tryConsume('a', 100), true);
    quota.refund('a', 100);
    assert.equal(quota.tryConsume('a', 100), true);
  });
});

describe('allowedVoiceIds', () => {
  it('une la lista configurada y la voz por defecto', () => {
    const ids = allowedVoiceIds(' v1, v2 ,,', 'def');
    assert.deepEqual([...ids].sort(), ['def', 'v1', 'v2']);
  });

  it('sin lista ni voz por defecto no permite ninguna', () => {
    assert.equal(allowedVoiceIds(undefined, undefined).size, 0);
  });
});
