import { createHash } from 'node:crypto';
import { eq, lt } from 'drizzle-orm';
import { getDb } from '../db/client.js';
import { revokedTokens } from '../db/schema.js';

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export async function revokeToken(token: string, userId: string, expiresIn: string, type: 'access' | 'refresh' = 'refresh'): Promise<void> {
  const db = getDb();
  if (!db) return;

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
  await db.insert(revokedTokens).values({
		tokenHash,
		userId,
		type,
		expiresAt
  });
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