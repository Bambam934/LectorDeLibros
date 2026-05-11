import type { FastifyReply, FastifyRequest } from 'fastify';
import { isTokenRevoked } from './token-revocation.js';

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

 const rawToken = request.headers.authorization?.replace('Bearer ', '') ?? '';
 if (rawToken) {
 try {
 if (await isTokenRevoked(rawToken)) {
 return reply.code(401).send({
 error: 'Unauthorized',
 message: 'Token de acceso ha sido revocado.'
 });
 }
 } catch {
 // If revocation check fails (e.g. DB down), allow the request through.
 // The 15-min access token TTL limits the risk window.
 }
 }
}
