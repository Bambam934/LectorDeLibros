import type { FastifyReply, FastifyRequest } from 'fastify';

export async function requireAccessToken(request: FastifyRequest, reply: FastifyReply) {
  try {
    await request.jwtVerify();
  } catch {
    return reply.code(401).send({
      error: 'Unauthorized',
      message: 'Token de acceso invalido o ausente.'
    });
  }

  if (request.user.type !== 'access') {
    return reply.code(401).send({
      error: 'Unauthorized',
      message: 'El token enviado no es un access token.'
    });
  }
}
