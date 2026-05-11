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
      type: 'access'
    },
    { expiresIn: ACCESS_TOKEN_TTL }
  );
}

export function createRefreshToken(app: FastifyInstance, user: AuthUser): string {
  return app.jwt.sign(
    {
      sub: user.id,
      email: user.email,
      type: 'refresh'
    },
    { expiresIn: REFRESH_TOKEN_TTL }
  );
}

export function getAuthenticatedUser(request: FastifyRequest) {
  return request.user;
}
