import { randomBytes, scrypt, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';

const scryptAsync = promisify(scrypt);
const KEY_LEN = 64;

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16).toString('hex');
  const hash = (await scryptAsync(password, salt, KEY_LEN)) as Buffer;
  return `${salt}:${hash.toString('hex')}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [salt, storedHash] = stored.split(':');
  if (!salt || !storedHash) return false;
  const hash = (await scryptAsync(password, salt, KEY_LEN)) as Buffer;
  const storedBuf = Buffer.from(storedHash, 'hex');
  if (hash.length !== storedBuf.length) return false;
  return timingSafeEqual(hash, storedBuf);
}
