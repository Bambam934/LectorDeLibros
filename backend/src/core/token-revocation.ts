import { createHash } from 'node:crypto';
import { eq, lt } from 'drizzle-orm';
import { getDb } from '../db/client.js';
import { revokedTokens } from '../db/schema.js';

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/**
 * Revoca el token. Devuelve true si ESTA llamada lo revocó y false si ya
 * estaba revocado: el INSERT es atómico (token_hash es único), así que de dos
 * refresh simultáneos con el mismo token solo uno obtiene true.
 */
export async function revokeToken(token: string, userId: string, expiresIn: string, type: 'access' | 'refresh' = 'refresh'): Promise<boolean> {
  const db = getDb();
  if (!db) return false;

  const expiresAt = new Date();
  const match = expiresIn.match(/^(\d+)([mhd])$/);
  if (match && match[1] && match[2]) {
    const value = parseInt(match[1], 10);
    switch (match[2]) {
      case 'm': expiresAt.setMinutes(expiresAt.getMinutes() + value); break;
      case 'h': expiresAt.setHours(expiresAt.getHours() + value); break;
      case 'd': expiresAt.setDate(expiresAt.getDate() + value); break;
    }
  }

  const tokenHash = hashToken(token);
  const inserted = await db
    .insert(revokedTokens)
    .values({
      tokenHash,
      userId,
      type,
      expiresAt
    })
    .onConflictDoNothing({ target: revokedTokens.tokenHash })
    .returning({ id: revokedTokens.id });
  return inserted.length > 0;
}

export async function isTokenRevoked(token: string): Promise<boolean> {
  const db = getDb();
  if (!db) return false;

  const tokenHash = hashToken(token);
  const result = await db
    .select({ id: revokedTokens.id })
    .from(revokedTokens)
    .where(eq(revokedTokens.tokenHash, tokenHash))
    .limit(1);

  return result.length > 0;
}

export async function cleanupExpiredTokens(): Promise<void> {
  const db = getDb();
  if (!db) return;

  await db.delete(revokedTokens).where(lt(revokedTokens.expiresAt, new Date()));
}