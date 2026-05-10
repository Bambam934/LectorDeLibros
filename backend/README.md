# LectorSync Backend

Backend inicial para LectorSync usando Fastify + TypeScript + Drizzle.

## Requisitos

- Node.js 22+
- npm 10+
- PostgreSQL (siguiente paso)

## Arranque rapido

```bash
cd backend
cp .env.example .env
npm install
npm run dev
```

Servidor local: http://127.0.0.1:3000

## Endpoints base (MVP)

- `GET /api/v1/health`
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `GET /api/v1/library`
- `POST /api/v1/library/import`
- `POST /api/v1/books/:bookId/chapters/:chapterId/audio`
- `PUT /api/v1/books/:bookId/progress`

## Base de datos local (PostgreSQL + Drizzle)

```bash
# 1) Inicia Docker Desktop
# 2) Levanta PostgreSQL
npm run db:up

# 3) Genera y aplica migraciones
npm run db:generate
npm run db:migrate

# 4) Inserta datos demo
npm run db:seed

# 5) Cuando termines
npm run db:down
```

## Scripts

- `npm run dev`: entorno de desarrollo
- `npm test`: pruebas de integracion de rutas v1
- `npm run typecheck`: chequeo de tipos
- `npm run build`: build para produccion
- `npm run start`: ejecutar build compilado
- `npm run db:generate`: generar migraciones SQL desde schema
- `npm run db:migrate`: aplicar migraciones en DATABASE_URL
- `npm run db:seed`: insertar datos demo de desarrollo
- `npm run db:up`: iniciar PostgreSQL local con Docker
- `npm run db:down`: detener servicios locales de Docker

## Estado

- API base operativa
- Registro de usuario operativo con `POST /api/v1/auth/register`
- Autenticacion JWT activa en rutas privadas
- Persistencia con Drizzle lista cuando DATABASE_URL esta disponible
- Endpoint de audio usa cache en `chapter_audio` (generated/cache/fallback)
- Contrato OpenAPI inicial en `openapi/openapi.yaml`
- Esquema inicial Drizzle en `src/db/schema.ts`

## Notas de respuesta API

- `POST /api/v1/auth/register`
  - `201` cuando crea usuario
  - `409` si el email ya existe
- Errores de validacion de entrada (Zod) devuelven:
  - `400`
  - `{ error: "ValidationError", message, details }`

## Siguiente bloque de trabajo

1. Implementar revocacion real de refresh tokens en logout.
2. Agregar validacion estricta de archivos para import (MIME + size).
3. Integrar proveedor TTS real para poblar `word_timestamps`.
4. Agregar mas pruebas de integracion para rutas de progress/audio.

## Notas de autenticacion

- `POST /api/v1/auth/login` entrega access token (15m) y refresh token (30d).
- Rutas privadas usan `Authorization: Bearer <access_token>`.
- Si `DATABASE_URL` no esta configurado, las rutas privadas funcionan en modo sin persistencia.
