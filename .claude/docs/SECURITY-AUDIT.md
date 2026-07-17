# LectorSync — Postura de seguridad

*Última actualización: 2026-07-16*

> Este documento reemplaza a la auditoría automática de 2026-05-09, que quedó obsoleta (reportaba como ALTAS vulnerabilidades ya remediadas). El detalle completo de las 14 vulnerabilidades y su remediación vive en la memoria del proyecto (`memory/security_audit_2026_05.md`).

## Resumen

Auditoría mayor: 2026-05-17 — **14 vulnerabilidades** (4 críticas, 5 altas, 3 medias, 2 bajas). Estado: **12 completamente remediadas**, 2 parciales, 1 aceptada con documentación. Revisión de seguimiento: 2026-07-16.

## Controles vigentes (NO regresar)

- **Contraseñas**: `scrypt` + `timingSafeEqual` con salt por usuario (`core/password.ts`).
- **JWT**: access 15 min + refresh 30 días, rotación en `/refresh`, revocación bidireccional verificada en cada request (`core/token-revocation.ts`).
- **Auth fail-closed**: sin `DATABASE_URL` en prod → 503, no 500 con detalles.
- **CORS**: deniega todo en prod si `CORS_ORIGINS` está vacío (`app.ts`).
- **Rate-limit diferenciado**: auth 5/15 min, resto 100/1 min, por IP.
- **Path traversal**: `voice_id` con regex `/^[a-zA-Z0-9_-]+$/` + `path.resolve` + `startsWith(AUDIO_DIR)`.
- **Límites de import**: 500 capítulos, 5M palabras, 50 MB; validación por magic bytes.
- **helmet**: CSP + HSTS en producción.
- **Postgres**: expuesto solo en `127.0.0.1:5432` (no a la LAN).
- **Parser EPUB**: DOCTYPE stripping contra XML bombs; sax bloquea XXE.

## Pendientes conocidos

| ID | Tema | Estado | Nota |
|---|---|---|---|
| **SEC-01** | `JWT_SECRET` con default hardcoded en `docker-compose.yml` | 🔴 En remediación (2026-07-16) | Un `docker compose up` sin `.env` usa un secreto presente en el repo. Se está quitando el fallback para forzar configuración explícita. |
| V-11 | Entity expansion en XML | 🟡 Parcial | sax bloquea XXE pero no toda expansión interna de entidades. |
| V-05 | Backend en `0.0.0.0:3000` | 🟡 Intencional | Expuesto a la LAN a propósito para pruebas con dispositivo físico; endurecer antes de producción. |
| V-10 | `localStorage`/IndexedDB en web para tokens | 🟢 Aceptado | Riesgo XSS documentado; recomendación BFF (httpOnly cookies) para producción. |

## Antes de producción

1. Cerrar SEC-01 (sin defaults de secretos).
2. Rotar `JWT_SECRET` y `POSTGRES_PASSWORD` reales vía secrets del orquestador, nunca en el repo.
3. Endurecer exposición del backend (reverse proxy/TLS; no `0.0.0.0` directo).
4. Evaluar BFF para la web (V-10).
5. Completar mitigación de entity expansion (V-11).

## Cómo auditar

Usar el comando global `/seguridad` (revisión defensiva priorizada con evidencia `archivo:línea`). No confiar en documentos congelados: la fuente de verdad es el código + esta tabla + la memoria.
