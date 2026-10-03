/**
 * Oculta el JWT que el cliente web manda en la query del SSE.
 *
 * `EventSource` no admite cabeceras, así que `/api/v1/sync/stream` recibe el
 * token como `?access_token=…` (ver `api/v1/routes/sync.ts`). El logger por
 * defecto de Fastify registra la URL completa de cada petición, y el token de
 * acceso acababa en claro en los logs del servidor: cualquiera con acceso a
 * ellos podía reutilizarlo mientras siguiera vigente.
 */
export function redactAccessToken(url: string): string {
  return url.replace(/([?&]access_token=)[^&#]*/gi, '$1[oculto]');
}
