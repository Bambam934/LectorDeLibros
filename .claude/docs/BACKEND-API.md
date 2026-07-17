# API y arquitectura del backend

*Última actualización: 2026-07-16 · Fastify 5 · TypeScript 5.7 · Drizzle ORM · PostgreSQL 16*

## Reglas y patrones

1. **Stack**: Fastify (HTTP), Drizzle ORM (PostgreSQL), Docker para Postgres local. Tests con el runner nativo de Node (`tsx --test`), no Postman.
2. **Capas**: HTTP en `src/api/v1/routes.ts` → lógica en `src/core/` → datos en `src/db/` (schema Drizzle). El HTTP nunca consulta la DB directamente.
3. **Autenticación**:
   - Contraseñas con **`scrypt` + `timingSafeEqual`** (`core/password.ts`) — formato `salt:hash`. NO bcrypt.
   - JWT access (15 min) + refresh (30 días) con rotación en `/refresh` y revocación bidireccional (`core/token-revocation.ts`).
   - Los tokens viajan en el body JSON; el middleware `requireAccessToken` verifica firma + revocación en cada request protegida.
4. **Validación**: Zod en cada payload y en `core/env.ts`. Sin `DATABASE_URL` en producción el arranque falla (fail-closed).
5. **Seguridad de transporte**: `helmet` (CSP/HSTS en prod), CORS que deniega todo en prod si `CORS_ORIGINS` está vacío, rate-limit diferenciado (auth 5/15 min, resto 100/1 min).

## Endpoints (v1)

Todas las rutas cuelgan de `/api/v1`. 🔒 = requiere access token.

### Salud
- `GET /health` — estado del servicio.

### Auth
- `POST /auth/register` — `{ name, email, password }` → `201` + tokens.
- `POST /auth/login` — `{ email, password }` → `200` + `{ accessToken, refreshToken }`.
- `POST /auth/refresh` — `{ refresh_token }` → nuevos tokens (rota y revoca el anterior).
- `POST /auth/logout` 🔒 — `{ refresh_token }` → revoca access **y** refresh.

### Biblioteca
- `GET /library` 🔒 — lista los libros del usuario.
- `POST /library/import` 🔒 — multipart, archivo EPUB/PDF/TXT/MD (máx. 50 MB). Límites: 500 capítulos, 5M palabras. Valida formato por magic bytes.
- `DELETE /books/:bookId` 🔒 — elimina el libro y sus datos.

### Lector
- `GET /books/:bookId/chapters` 🔒 — lista de capítulos.
- `GET /books/:bookId/chapters/:chapterId` 🔒 — texto del capítulo.
- `POST /books/:bookId/chapters/:chapterId/audio` 🔒 — genera (o devuelve cacheado) el audio TTS del capítulo. `voice_id` validado con `/^[a-zA-Z0-9_-]+$/`.
- `PUT /books/:bookId/progress` 🔒 — guarda la posición de lectura y **publica el evento en el bus de sync**.

### Audio y sincronización
- `GET /audio/:chapterId-:voiceId.mp3` 🔒 — sirve el archivo de audio (protegido contra path traversal: `resolve` + `startsWith`).
- `GET /sync/stream` 🔒 — **SSE** de progreso multi-dispositivo. Los navegadores pasan el JWT como `?access_token=…` (EventSource no admite headers); los clientes nativos usan `Authorization`.

## Base de datos

PostgreSQL 16 con Drizzle. Tablas: `users`, `books`, `chapters`, `chapter_audio`, `reading_progress`, `revoked_tokens`. Migraciones en `drizzle/`.

Comandos: `npm run db:up` (Postgres), `db:generate` / `db:migrate` / `db:push` / `db:studio` / `db:seed`.

## Variables de entorno

Definidas y validadas en `core/env.ts`. Obligatorias en prod: `DATABASE_URL`, `JWT_SECRET` (≥32 chars). Opcionales: `NVIDIA_API_KEY`, `ELEVENLABS_API_KEY`, `TTS_PROVIDER` (`elevenlabs`|`mock`), `CORS_ORIGINS`. Ver `.env.example`.
