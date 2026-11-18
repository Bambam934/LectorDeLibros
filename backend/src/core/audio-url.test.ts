import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { AUDIO_URL_TTL_MS, parseAudioFileName, signedAudioUrl, verifyAudioSignature } from './audio-url.js';
import { redactAccessToken } from './log-redaction.js';

const chapterId = '3f2b8c1e-9a4d-4e6f-8b2a-1c3d5e7f9a0b';
const userId = '7a1b2c3d-4e5f-4a6b-9c8d-0e1f2a3b4c5d';

function parts(url: string) {
  const u = new URL(url, 'http://x');
  return {
    path: u.pathname,
    u: u.searchParams.get('u')!,
    exp: Number(u.searchParams.get('exp')),
    sig: u.searchParams.get('sig')!
  };
}

describe('URLs de audio firmadas', () => {
  it('separa el UUID con guiones de la voz', () => {
    assert.deepEqual(parseAudioFileName(`${chapterId}-voz_1.mp3`), { chapterId, voiceId: 'voz_1' });
    assert.deepEqual(parseAudioFileName(`${chapterId}-voz-con-guiones.mp3`), {
      chapterId,
      voiceId: 'voz-con-guiones'
    });
    assert.equal(parseAudioFileName('../../etc/passwd'), null);
    assert.equal(parseAudioFileName(`${chapterId}-voz.wav`), null);
  });

  it('acepta su propia firma y rechaza cualquier cambio', () => {
    const now = Date.parse('2026-11-17T10:00:00Z');
    const { path, u, exp, sig } = parts(signedAudioUrl(chapterId, 'voz', userId, now));
    assert.equal(path, `/api/v1/audio/${chapterId}-voz.mp3`);
    assert.equal(u, userId);
    assert.equal(verifyAudioSignature(chapterId, 'voz', userId, exp, sig, now), true);

    assert.equal(verifyAudioSignature(chapterId, 'otra', userId, exp, sig, now), false);
    assert.equal(verifyAudioSignature(chapterId, 'voz', crypto.randomUUID(), exp, sig, now), false);
    assert.equal(verifyAudioSignature(chapterId, 'voz', userId, exp + 3600, sig, now), false);
    assert.equal(verifyAudioSignature(chapterId, 'voz', userId, exp, `${sig}x`, now), false);
  });

  it('caduca a las 12 horas', () => {
    const now = Date.parse('2026-11-17T10:00:00Z');
    const { exp, sig } = parts(signedAudioUrl(chapterId, 'voz', userId, now));
    assert.equal(verifyAudioSignature(chapterId, 'voz', userId, exp, sig, now + AUDIO_URL_TTL_MS - 1000), true);
    assert.equal(verifyAudioSignature(chapterId, 'voz', userId, exp, sig, now + AUDIO_URL_TTL_MS + 1000), false);
  });

  it('la firma no llega a los logs', () => {
    const url = signedAudioUrl(chapterId, 'voz', userId);
    const redacted = redactAccessToken(url);
    assert.match(redacted, /sig=\[oculto\]/);
    assert.ok(!redacted.includes(parts(url).sig));
  });
});
