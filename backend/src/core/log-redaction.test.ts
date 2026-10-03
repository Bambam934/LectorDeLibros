import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { redactAccessToken } from './log-redaction.js';

describe('log-redaction — redactAccessToken', () => {
  it('oculta el token de la query del SSE', () => {
    assert.equal(
      redactAccessToken('/api/v1/sync/stream?access_token=eyJhbGciOi.abc.def'),
      '/api/v1/sync/stream?access_token=[oculto]',
    );
  });

  it('conserva el resto de parámetros', () => {
    assert.equal(
      redactAccessToken('/api/v1/sync/stream?client=web&access_token=secreto&v=2'),
      '/api/v1/sync/stream?client=web&access_token=[oculto]&v=2',
    );
  });

  it('deja intactas las URLs sin token', () => {
    const url = '/api/v1/books/123/progress?word=40';
    assert.equal(redactAccessToken(url), url);
  });

  it('no confunde otro parámetro que termine igual', () => {
    const url = '/x?not_access_token=1';
    assert.equal(redactAccessToken(url), url);
  });
});
