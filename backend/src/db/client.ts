import 'dotenv/config';
import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';

import { env } from '../core/env.js';
import * as schema from './schema.js';

const DATABASE_UNAVAILABLE_REASON =
  'DATABASE_URL no configurado; se ejecuta en modo sin persistencia.';

let pool: Pool | null = null;
let dbInstance: ReturnType<typeof drizzle<typeof schema>> | null = null;

if (env.DATABASE_URL) {
  pool = new Pool({ connectionString: env.DATABASE_URL });
  dbInstance = drizzle(pool, { schema });
}

export function getDb() {
  return dbInstance;
}

export function getDatabaseUnavailableReason() {
  return DATABASE_UNAVAILABLE_REASON;
}
