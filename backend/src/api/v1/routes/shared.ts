import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';

/** Reads the originating device's clientId from headers. Clients should
 *  generate a stable UUID at first launch and resend it on every mutation.
 *  Used so the SSE push for a write can be tagged with its originator,
 *  letting that same device discard the echo instead of double-applying
 *  its own change. Missing/empty header is fine — the event just won't
 *  carry an originator and every connected device (including the writer)
 *  will treat it as fresh. */
export function readClientId(request: { headers: Record<string, unknown> }): string | undefined {
  const raw = request.headers['x-client-id'];
  if (typeof raw !== 'string') return undefined;
  const trimmed = raw.trim();
  if (!trimmed) return undefined;
  // Cap the length so we don't store a 10MB blob as a clientId.
  return trimmed.slice(0, 128);
}

const DB_ERROR_CODES = [
  'ECONNREFUSED',
  'ECONNRESET',
  'ENOTFOUND',
  'ETIMEDOUT',
  '57P03',
  '08001',
  '08003',
  '08004',
  '08006',
  '08007'
];

export function isDbConnectionError(err: unknown): boolean {
  const seen = new Set<unknown>();
  let current: unknown = err;
  for (let depth = 0; depth < 10 && current != null; depth++) {
    if (seen.has(current)) break;
    seen.add(current);
    if (current instanceof Error) {
      const anyErr = current as { code?: string; errno?: string; name?: string };
      if (DB_ERROR_CODES.includes(anyErr.code ?? '') || DB_ERROR_CODES.includes(anyErr.errno ?? '')) {
        return true;
      }
      const msg = current.message?.toLowerCase() ?? '';
      if (
        msg.includes('econnrefused') ||
        msg.includes('connection refused') ||
        msg.includes('connection terminated') ||
        msg.includes('cannot connect')
      ) {
        return true;
      }
      if (current instanceof AggregateError && Array.isArray(current.errors)) {
        for (const inner of current.errors) {
          if (isDbConnectionError(inner)) return true;
        }
      }
      current = (current as { cause?: unknown }).cause;
    } else {
      current = (current as { cause?: unknown })?.cause;
    }
  }
  return false;
}

export function dbUnavailableReply() {
  return {
    error: 'ServiceUnavailable' as const,
    message: 'Servicio no disponible: no se puede conectar a la base de datos.'
  };
}

/** Compartido por library (borrado) y reader (capítulos, progreso). */
export const bookParamsSchema = z.object({ bookId: z.string().uuid() });

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// Tres niveles: este archivo vive en src/api/v1/routes/, el storage en src/.
export const AUDIO_DIR = path.join(__dirname, '..', '..', '..', 'storage', 'audio');

export function getAudioFilePath(chapterId: string, voiceId: string): string {
  const resolved = path.resolve(AUDIO_DIR, `${chapterId}-${voiceId}.mp3`);
  if (!resolved.startsWith(AUDIO_DIR)) {
    throw new Error('Path traversal detected');
  }
  return resolved;
}

export function getAudioUrlPath(chapterId: string, voiceId: string): string {
  return `/api/v1/audio/${chapterId}-${voiceId}.mp3`;
}

export async function saveAudioFile(filePath: string, buffer: Buffer): Promise<void> {
  await fs.promises.mkdir(path.dirname(filePath), { recursive: true });
  await fs.promises.writeFile(filePath, buffer);
}
