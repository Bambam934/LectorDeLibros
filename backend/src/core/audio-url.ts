import { createHash, createHmac, timingSafeEqual } from 'node:crypto';

import { env } from './env.js';

/**
 * URLs firmadas para descargar el audio de un capítulo.
 *
 * El reproductor (just_audio) pide la URL sin cabeceras: en web y en Windows
 * no puede mandar `Authorization`. En vez de meter el token de sesión en la
 * URL, el POST que comprueba que el libro es del usuario devuelve una URL con
 * caducidad y una firma HMAC ligada a capítulo, voz y usuario. El GET solo
 * sirve el archivo si la firma cuadra y no ha caducado.
 */

/** Un capítulo largo puede durar más de una hora, con pausas y saltos. */
export const AUDIO_URL_TTL_MS = 12 * 60 * 60_000;

// Clave propia derivada del secreto del JWT: una firma de audio nunca sirve
// como JWT ni al revés.
const key = createHash('sha256').update(`lectorsync:audio-url:${env.JWT_SECRET}`).digest();

function sign(chapterId: string, voiceId: string, userId: string, exp: number): string {
  return createHmac('sha256', key)
    .update(`${chapterId}\n${voiceId}\n${userId}\n${exp}`)
    .digest('base64url');
}

export function signedAudioUrl(
  chapterId: string,
  voiceId: string,
  userId: string,
  now = Date.now()
): string {
  const exp = Math.floor((now + AUDIO_URL_TTL_MS) / 1000);
  const sig = sign(chapterId, voiceId, userId, exp);
  const query = new URLSearchParams({ u: userId, exp: String(exp), sig });
  return `/api/v1/audio/${chapterId}-${voiceId}.mp3?${query.toString()}`;
}

export function verifyAudioSignature(
  chapterId: string,
  voiceId: string,
  userId: string,
  exp: number,
  sig: string,
  now = Date.now()
): boolean {
  if (!Number.isInteger(exp) || exp * 1000 < now) return false;
  const expected = Buffer.from(sign(chapterId, voiceId, userId, exp));
  const given = Buffer.from(sig);
  return expected.length === given.length && timingSafeEqual(expected, given);
}

const FILE_NAME_RE = /^([0-9a-fA-F-]{36})-([a-zA-Z0-9_-]{1,100})\.mp3$/;

/**
 * Separa `<uuid>-<voz>.mp3`. No vale un patrón `:chapterId-:voiceId` de
 * Fastify: corta en el primer guion y el UUID tiene cuatro.
 */
export function parseAudioFileName(fileName: string): { chapterId: string; voiceId: string } | null {
  const match = FILE_NAME_RE.exec(fileName);
  if (!match?.[1] || !match[2]) return null;
  return { chapterId: match[1], voiceId: match[2] };
}
