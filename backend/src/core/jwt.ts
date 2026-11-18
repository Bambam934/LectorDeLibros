import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';

export const ACCESS_TOKEN_TTL = '15m';
export const REFRESH_TOKEN_TTL = '30d';

type AuthUser = {
  id: string;
  email: string;
};

export function createAccessToken(app: FastifyInstance, user: AuthUser): string {
  return app.jwt.sign(
    {
      sub: user.id,
      email: user.email,
      type: 'access',
      jti: randomUUID()
    },
    { expiresIn: ACCESS_TOKEN_TTL }
  );
}

export function createRefreshToken(app: FastifyInstance, user: AuthUser): string {
  return app.jwt.sign(
    {
      sub: user.id,
      email: user.email,
      type: 'refresh',
      // Sin jti, dos refresh del mismo usuario en el mismo segundo salían
      // idénticos: revocar uno revocaba el otro, y la rotación no distinguía.
      jti: randomUUID()
    },
    { expiresIn: REFRESH_TOKEN_TTL }
  );
}

export function getAuthenticatedUser(request: FastifyRequest) {
  return request.user;
}
