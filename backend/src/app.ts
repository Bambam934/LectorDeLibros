import 'dotenv/config';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import jwt from '@fastify/jwt';
import multipart from '@fastify/multipart';
import rateLimit from '@fastify/rate-limit';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import Fastify, { type FastifyInstance } from 'fastify';

import { registerV1Routes } from './api/v1/routes.js';
import { cleanupExpiredTokens } from './core/token-revocation.js';
import { env } from './core/env.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const AUDIO_DIR = path.join(__dirname, 'storage', 'audio');

const corsOrigins = (env.CORS_ORIGINS ?? '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

/** Convierte valores como "1 minute" / "15 minute" a ms (requerido por @fastify/rate-limit cuando timeWindow es función). */
function durationToMs(value: string): number {
  const trimmed = value.trim();
  const match = trimmed.match(
    /^(\d+)\s*(milliseconds?|ms|seconds?|s|minutes?|m|hours?|h|days?|d)?$/i
  );
  if (!match?.[1]) return 60_000;
  const n = parseInt(match[1], 10);
  const unit = (match[2] ?? 'm').toLowerCase();
  if (unit === 'ms' || unit.startsWith('millisecond')) return n;
  if (unit === 's' || unit.startsWith('second')) return n * 1000;
  if (unit === 'm' || unit.startsWith('minute')) return n * 60_000;
  if (unit === 'h' || unit.startsWith('hour')) return n * 3_600_000;
  if (unit === 'd' || unit.startsWith('day')) return n * 86_400_000;
  return n * 60_000;
}

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: env.NODE_ENV !== 'test' });

  if (env.HELMET_ENABLED) {
    await app.register(helmet, {
      contentSecurityPolicy: env.NODE_ENV === 'production',
      hsts: env.NODE_ENV === 'production' ? { maxAge: 31536000, includeSubDomains: true } : false
    });
  }

	await app.register(cors, {
		origin: env.NODE_ENV === 'production'
			? (corsOrigins.length > 0 ? corsOrigins : false)
			: (corsOrigins.length > 0 ? corsOrigins : true),
		credentials: true,
		methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
		allowedHeaders: ['Content-Type', 'Authorization']
	});

  await app.register(rateLimit, {
    max: (req) =>
      req.url.includes('/api/v1/auth/') ? env.AUTH_RATE_LIMIT_MAX : env.RATE_LIMIT_MAX,
    timeWindow: (req) =>
      req.url.includes('/api/v1/auth/')
        ? durationToMs(env.AUTH_RATE_LIMIT_WINDOW)
        : durationToMs(env.RATE_LIMIT_WINDOW),
    keyGenerator: (req) => {
      if (req.url.includes('/api/v1/auth/')) {
        return `auth:${req.ip}`;
      }
      return req.ip;
    }
  });

	await app.register(multipart, {
		limits: {
			fileSize: 50 * 1024 * 1024
		}
	});

	await app.register(jwt, {
    secret: env.JWT_SECRET
  });

	await registerV1Routes(app);

	setInterval(() => {
		cleanupExpiredTokens().catch((err) => {
			app.log.error(err, 'Failed to cleanup expired tokens');
		});
	}, 60 * 60_000).unref();

	return app;
}
