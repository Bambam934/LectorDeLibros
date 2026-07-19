import { eq } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { requireAccessToken } from '../../../core/auth.js';
import {
  ACCESS_TOKEN_TTL,
  createAccessToken,
  createRefreshToken,
  getAuthenticatedUser,
  REFRESH_TOKEN_TTL
} from '../../../core/jwt.js';
import { hashPassword, verifyPassword } from '../../../core/password.js';
import { isTokenRevoked, revokeToken } from '../../../core/token-revocation.js';
import { getDb } from '../../../db/client.js';
import { users } from '../../../db/schema.js';
import { dbUnavailableReply, isDbConnectionError } from './shared.js';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8)
});

const registerSchema = z.object({
  name: z.string().min(1).max(255),
  email: z.string().email(),
  password: z.string().min(8)
});

const refreshSchema = z.object({
  refresh_token: z.string().min(1)
});

const logoutSchema = z.object({
  refresh_token: z.string().min(1).optional()
});

export function registerAuthRoutes(app: FastifyInstance): void {
  app.post('/api/v1/auth/register', async (request, reply) => {
    const body = registerSchema.parse(request.body);
    const db = getDb();

    if (!db) {
      return reply.code(503).send(dbUnavailableReply());
    }

    try {
      const existingUser = await db
        .select({ id: users.id, passwordHash: users.passwordHash })
        .from(users)
        .where(eq(users.email, body.email))
        .limit(1);

      if (existingUser[0]) {
        if (!existingUser[0].passwordHash) {
          const passwordHash = await hashPassword(body.password);
          await db
            .update(users)
            .set({ passwordHash })
            .where(eq(users.id, existingUser[0].id));
          return reply.code(201).send({ id: existingUser[0].id, email: body.email, name: body.name });
        }

        return reply.code(409).send({
          error: 'Conflict',
          message: 'Ya existe una cuenta con ese correo.'
        });
      }

      const passwordHash = await hashPassword(body.password);

      const createdUser = await db
        .insert(users)
        .values({ email: body.email, name: body.name, passwordHash })
        .returning({ id: users.id, email: users.email, name: users.name });

      return reply.code(201).send(createdUser[0]);
    } catch (err) {
      if (isDbConnectionError(err)) {
        return reply.code(503).send(dbUnavailableReply());
      }
      throw err;
    }
  });

  app.post('/api/v1/auth/login', async (request, reply) => {
    const body = loginSchema.parse(request.body);
    const db = getDb();

    if (!db) {
      return reply.code(503).send(dbUnavailableReply());
    }

    try {
      const result = await db
        .select({ id: users.id, email: users.email, passwordHash: users.passwordHash })
        .from(users)
        .where(eq(users.email, body.email))
        .limit(1);

      const user = result[0];

      if (!user || !user.passwordHash) {
        return reply.code(401).send({
          error: 'Unauthorized',
          message: 'Credenciales inválidas.'
        });
      }

      const valid = await verifyPassword(body.password, user.passwordHash);
      if (!valid) {
        return reply.code(401).send({
          error: 'Unauthorized',
          message: 'Credenciales inválidas.'
        });
      }

      return reply.send({
        access_token: createAccessToken(app, { id: user.id, email: user.email }),
        refresh_token: createRefreshToken(app, { id: user.id, email: user.email }),
        expires_in: 900
      });
    } catch (err) {
      if (isDbConnectionError(err)) {
        return reply.code(503).send(dbUnavailableReply());
      }
      throw err;
    }
  });

  app.post('/api/v1/auth/refresh', async (request, reply) => {
    const body = refreshSchema.parse(request.body ?? {});

    try {
      if (await isTokenRevoked(body.refresh_token)) {
        return reply.code(401).send({
          error: 'Unauthorized',
          message: 'Token ha sido revocado.'
        });
      }
    } catch {
      // If revocation check fails (DB down), continue to JWT verification
      // so we can still reject wrong token types with proper 401
    }

    let payload: { sub: string; email: string; type: 'access' | 'refresh' };
    try {
      payload = await app.jwt.verify(body.refresh_token);
    } catch {
      return reply.code(401).send({
        error: 'Unauthorized',
        message: 'Refresh token invalido o expirado.'
      });
    }

    if (payload.type !== 'refresh') {
      return reply.code(401).send({
        error: 'Unauthorized',
        message: 'El token enviado no es un refresh token.'
      });
    }

    const db = getDb();
    if (!db) {
      return reply.code(503).send(dbUnavailableReply());
    }

    try {
      await revokeToken(body.refresh_token, payload.sub, REFRESH_TOKEN_TTL, 'refresh');
    } catch (err) {
      if (isDbConnectionError(err)) {
        return reply.code(503).send(dbUnavailableReply());
      }
      throw err;
    }

    try {
      const result = await db
        .select({ id: users.id, email: users.email })
        .from(users)
        .where(eq(users.id, payload.sub))
        .limit(1);

      const user = result[0];
      if (!user) {
        return reply.code(401).send({
          error: 'Unauthorized',
          message: 'Usuario no encontrado.'
        });
      }

      return reply.send({
        access_token: createAccessToken(app, { id: user.id, email: user.email }),
        refresh_token: createRefreshToken(app, { id: user.id, email: user.email }),
        expires_in: 900
      });
    } catch (err) {
      if (isDbConnectionError(err)) {
        return reply.code(503).send(dbUnavailableReply());
      }
      throw err;
    }
  });

  app.post('/api/v1/auth/logout', { preHandler: requireAccessToken }, async (request, reply) => {
    const body = logoutSchema.parse(request.body ?? {});
    const authUser = getAuthenticatedUser(request);
    const db = getDb();

    if (db && authUser) {
      const rawAccessToken = request.headers.authorization?.replace('Bearer ', '') ?? '';
      try {
        if (rawAccessToken) {
          await revokeToken(rawAccessToken, authUser.sub, ACCESS_TOKEN_TTL, 'access');
        }
        if (body.refresh_token) {
          await revokeToken(body.refresh_token, authUser.sub, REFRESH_TOKEN_TTL, 'refresh');
        }
      } catch {
        // If revocation persist fails (DB down), still return success.
        // Tokens will expire naturally (15m access / 30d refresh).
      }
    }

    return reply.code(204).send();
  });
}
