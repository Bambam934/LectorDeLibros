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
 // Falla cerrada: si no se puede saber si el token está revocado (DB
 // caída), no se deja pasar. 503 y no 401: el cliente no cierra la
 // sesión, solo reintenta más tarde.
 return reply.code(503).send({
 error: 'ServiceUnavailable',
 message: 'No se pudo verificar la sesión. Inténtalo de nuevo en unos segundos.'
 });
 }
 }
}
