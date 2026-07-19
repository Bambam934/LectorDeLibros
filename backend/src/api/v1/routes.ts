import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { env } from '../../core/env.js';
import { registerAuthRoutes } from './routes/auth.js';
import { registerLibraryRoutes } from './routes/library.js';
import { registerReaderRoutes } from './routes/reader.js';
import { registerSyncRoutes } from './routes/sync.js';

/**
 * Compositor de la API v1. El manejo de errores y el health check viven
 * aquí; cada dominio registra sus rutas desde `./routes/<dominio>.ts`.
 */
export async function registerV1Routes(app: FastifyInstance): Promise<void> {
  app.setErrorHandler((error, request, reply) => {
    if (error instanceof z.ZodError) {
      return reply.code(400).send({
        error: 'ValidationError',
        message: 'Datos de entrada invalidos',
        details: error.issues
      });
    }

    const fastifyErr = error as { statusCode?: number };
    if (fastifyErr.statusCode) {
      return reply.code(fastifyErr.statusCode).send(error);
    }

    request.log.error({ err: error }, 'Unhandled error');

    if (env.NODE_ENV === 'production') {
      return reply.code(500).send({
        error: 'InternalServerError',
        message: 'Error interno del servidor.'
      });
    }

    return reply.code(500).send({
      error: 'InternalServerError',
      message: error instanceof Error ? error.message : 'Error interno del servidor.'
    });
  });

  app.get('/api/v1/health', async () => ({
    ok: true,
    service: 'lectorsync-backend',
    timestamp: new Date().toISOString()
  }));

  registerAuthRoutes(app);
  registerLibraryRoutes(app);
  registerReaderRoutes(app);
  registerSyncRoutes(app);
}
