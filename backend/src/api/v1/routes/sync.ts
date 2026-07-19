import type { FastifyInstance } from 'fastify';

import { requireAccessToken } from '../../../core/auth.js';
import { getAuthenticatedUser } from '../../../core/jwt.js';
import { realtimeBus, type RealtimeEvent } from '../../../core/realtime-bus.js';

// ─────────────────────── REALTIME SYNC (SSE) ───────────────────────
//
// Long-lived Server-Sent Events stream per authenticated user.
// Clients open ONE connection at login and keep it open; the server
// fans out pub/sub events (progress updates, bookmark mutations) so
// device B is notified the instant device A writes. SSE was chosen
// over WebSocket because the channel is strictly server→client (no
// client messages) and SSE traverses HTTP proxies/CDNs without
// special handling.
//
// Heartbeat: a comment line (": ping\n\n") is written every 25 s to
// keep proxies (and Node's default socket timeout) from closing an
// otherwise-idle connection. Comments are ignored by EventSource.
export function registerSyncRoutes(app: FastifyInstance): void {
  app.get(
    '/api/v1/sync/stream',
    {
      preHandler: [
        // Browsers' EventSource cannot set custom headers, so the
        // web client passes the JWT as `?access_token=…`. We copy
        // it into the Authorization header BEFORE requireAccessToken
        // runs so the rest of the auth path is unchanged. Native
        // clients keep sending the Authorization header directly
        // (preferred — keeps the token out of access logs).
        async (request, _reply) => {
          if (request.headers.authorization) return;
          const q = (request.query as Record<string, unknown> | undefined)?.access_token;
          if (typeof q === 'string' && q.length > 0) {
            request.headers.authorization = `Bearer ${q}`;
          }
        },
        requireAccessToken
      ]
    },
    async (request, reply) => {
      const authUser = getAuthenticatedUser(request);

      // Bypass Fastify's content negotiation entirely — we own the
      // raw socket from here on so the response body can stay open.
      reply.raw.setHeader('Content-Type', 'text/event-stream');
      reply.raw.setHeader('Cache-Control', 'no-cache, no-transform');
      reply.raw.setHeader('Connection', 'keep-alive');
      // Disable proxy buffering (NGINX honours this; others ignore).
      reply.raw.setHeader('X-Accel-Buffering', 'no');
      reply.raw.flushHeaders();

      const write = (event: RealtimeEvent) => {
        // Guard against the small race between unsubscribe and a
        // publish on a different tick — a write after socket
        // close would throw and crash the listener.
        if (reply.raw.writableEnded) return;
        const payload = JSON.stringify(event);
        reply.raw.write(`event: ${event.type}\n`);
        reply.raw.write(`data: ${payload}\n\n`);
      };

      // Welcome frame so clients can detect "connected" without
      // waiting for the first business event. The non-standard
      // `__welcome` flag lets the client ignore it instead of
      // applying it as a real progress update.
      write({
        type: 'progress.updated',
        ts: new Date().toISOString(),
        data: { __welcome: true, userId: authUser.sub }
      } as RealtimeEvent);

      const unsubscribe = realtimeBus.subscribe(authUser.sub, write);

      const heartbeat = setInterval(() => {
        if (reply.raw.writableEnded) return;
        try {
          reply.raw.write(`: ping ${Date.now()}\n\n`);
        } catch {
          // Socket dead → cleanup fires from the close handler.
        }
      }, 25_000);
      heartbeat.unref?.();

      const cleanup = () => {
        clearInterval(heartbeat);
        unsubscribe();
      };

      request.raw.on('close', cleanup);
      request.raw.on('error', cleanup);

      // Returning the (still-open) reply tells Fastify we've
      // hijacked the response — it must not send anything else.
      return reply;
    }
  );
}
