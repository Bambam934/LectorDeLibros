# LectorSync — Guía de Onboarding

Aplicación full-stack de lectura sincronizada con audio de alta calidad. Multi-formato (EPUB, PDF, TXT, MD) con TTS palabra-a-palabra y soporte multiplataforma.

## Stack tecnológico

- **Frontend**: Flutter 3+ / Dart, BLoC, GetIt DI, GoRouter, Dio, just_audio, flutter_tts
- **Backend**: Fastify 5 / TypeScript 5.7, Drizzle ORM, PostgreSQL 16, Zod
- **TTS**: ElevenLabs (eleven_multilingual_v2) + device TTS nativo
- **AI**: NVIDIA GLM-5.1 via OpenAI SDK
- **Infra**: Docker Compose (PostgreSQL 16)

## Inicio rápido

```bash
# Backend
cd backend
cp .env.example .env          # Configurar JWT_SECRET (min 32 chars) y API keys
npm install
npm run db:up                 # PostgreSQL via Docker
npm run db:push               # Aplicar schema
npm run db:seed               # Datos demo
npm run dev                   # http://127.0.0.1:3000

# Frontend
cd lectorsync
flutter pub get
flutter run -d chrome         # Web
flutter run                   # Android/iOS
```

## Arquitectura

```
Flutter App (Clean Architecture)
  AuthCubit -> LibraryBloc -> ReaderBloc (TTS + Audio)
       |             |                |
  SecureStorage  RemoteRepo      RemoteReaderRepo
       |             |                |
       +---------- ApiClient (Dio + JWT interceptor) ----------+
                              |
                         HTTP / REST
                              |
               Fastify Backend (API v1)
                 Auth | Library | Reader
                   |       |        |
              Parsers   TTS Providers   GLM AI
                   |       |        |
               PostgreSQL 16 (Drizzle ORM)
```

### Backend: archivos clave

| Archivo | Responsabilidad |
|---------|----------------|
| `backend/src/server.ts` | Entry point |
| `backend/src/app.ts` | Fastify builder (CORS, helmet, rate-limit, JWT, errors) |
| `backend/src/api/v1/routes.ts` | Todos los endpoints API |
| `backend/src/core/auth.ts` | Middleware JWT + verificacion de tokens revocados |
| `backend/src/core/env.ts` | Validacion Zod de env vars |
| `backend/src/core/token-revocation.ts` | Blacklist de tokens (access + refresh) |
| `backend/src/core/parsers/` | EPUB, PDF, TXT, MD parsers |
| `backend/src/core/tts/` | ElevenLabs + Mock providers |
| `backend/src/core/glm.ts` | NVIDIA GLM-5.1 (resumenes, dialogos, limpieza texto) |
| `backend/src/db/schema.ts` | Drizzle ORM schema (6 tablas) |

### Flutter: features (domain/data/presentation)

| Feature | Estado | Archivos clave |
|---------|--------|----------------|
| **auth** | AuthCubit, login/register, JWT auto-refresh | `features/auth/` |
| **library** | LibraryBloc, import multipart, grid responsivo | `features/library/` |
| **reader** | ReaderBloc, TTS playback, word sync, auto-scroll | `features/reader/` |
| **settings** | PreferencesCubit, font/theme/voice prefs | `features/settings/` |

### TTS (lo mas complejo del proyecto)

- `TtsRepositoryProxy`: wrapper que delega a DeviceTts o AudioTts en runtime
- `DeviceTtsRepository`: flutter_tts nativo con segmentacion, auto-recovery, estimated progress
- `AudioTtsRepository`: ElevenLabs audio + just_audio playback con word timestamps
- `SegmentProgressTracker`: divide texto en segmentos, binary search para word index
- Adapters: `NativeMobileTtsAdapter`, `WebTtsAdapter`, `FakeTtsAdapter`

## Base de datos

6 tablas en PostgreSQL via Drizzle ORM:

- `users` — id, email, name, passwordHash, plan
- `books` — id, userId (FK), title, author, language, fileFormat, status, totalWords
- `chapters` — id, bookId (FK), title, orderIndex, wordCount, textContent
- `chapterAudio` — id, chapterId (FK), voiceId, ttsProvider, audioKey, durationMs, wordTimestamps (JSONB)
- `readingProgress` — id, userId (FK), bookId (FK), chapterId, wordIndex, audioPositionMs, percentage
- `revokedTokens` — id, tokenHash, userId (FK), type, expiresAt

## API Endpoints

### Auth (sin autenticacion)
- `POST /api/v1/auth/register` — Registro con email/password
- `POST /api/v1/auth/login` — Login, retorna access_token + refresh_token
- `POST /api/v1/auth/refresh` — Renovar access token (rota refresh token)
- `POST /api/v1/auth/logout` — Revoca access + refresh tokens

### Library (requiere JWT)
- `GET /api/v1/library` — Listar libros del usuario con progreso
- `POST /api/v1/library/import` — Import multipart (EPUB/PDF/TXT/MD, max 50MB, 500 caps, 5M palabras)
- `DELETE /api/v1/books/:bookId` — Eliminar libro

### Reader (requiere JWT)
- `GET /api/v1/books/:bookId/chapters` — Listar capitulos
- `GET /api/v1/books/:bookId/chapters/:chapterId` — Texto del capitulo
- `POST /api/v1/books/:bookId/chapters/:chapterId/audio` — Generar/obtener audio TTS
- `PUT /api/v1/books/:bookId/progress` — Guardar posicion de lectura
- `GET /api/v1/audio/:chapterId-:voiceId.mp3` — Servir archivo de audio (autenticado)

### Health
- `GET /api/v1/health` — Status del servicio

## Seguridad (auditoria mayo 2026)

14 vulnerabilidades identificadas, 12 completamente remediadas:

- Passwords: scrypt con salt aleatorio de 64 bytes
- JWT: HS256, access 15min, refresh 30d, revocacion bidireccional
- Rate limiting: 100 req/min general, 5 req/15min auth (por IP)
- CORS: origins explicitos en produccion, deniega todo si vacio
- Helmet: CSP + HSTS en produccion
- Input validation: Zod en todos los endpoints
- Path traversal: regex + path.resolve + startsWith
- Refresh token rotation: revoca viejo antes de emitir nuevo
- Cleanup automatico: tokens expirados cada hora

### Pendientes de seguridad
- Docker compose: usar `expose` en vez de `ports` para produccion
- XML bombs: prevenir entity expansion en EPUB parser
- Web storage: migrar a httpOnly cookies (BFF pattern) para produccion

## Responsive layouts

3 breakpoints: compact (<600px), medium (600-1199px), expanded (>=1200px)

- Library: single-column -> sidebar+grid -> NavigationRail+sidebar+grid
- Reader: Drawer TOC -> collapsible sidebar -> wider sidebar
- Keyboard: Space=play/pause, Left/Right=capitulo, T=toggle TOC

## Tests

- Backend: 52/52 passing (`npm test`) — routes, parsers, TTS providers
- Frontend: unit + widget tests en `test/` — segments, TTS capabilities, progress tracker
- Typecheck: `npm run typecheck` limpio
- Lint: `flutter analyze` 0 issues

## Variables de entorno (backend/.env)

```env
PORT=3000
HOST=127.0.0.1
NODE_ENV=development
DATABASE_URL=postgresql://user:password@localhost:5432/lectorsync
JWT_SECRET=<min 32 chars, generar con: node -e "console.log(require('crypto').randomBytes(64).toString('hex'))">
RATE_LIMIT_MAX=100
CORS_ORIGINS=http://localhost:3000
NVIDIA_API_KEY=<tu key de NVIDIA NIM>
ELEVENLABS_API_KEY=<tu key de ElevenLabs>
ELEVENLABS_DEFAULT_VOICE_ID=<voice ID>
```

## Convenciones

- **Backend**: TypeScript strict, Zod para validacion, Drizzle para DB, sin ORMs magicos
- **Frontend**: Clean Architecture, BLoC/Cubit, Either/Failure (fpdart), GetIt DI, sin dart:io en features
- **Git**: Conventional commits (`feat:`, `fix:`, `chore:`, `security:`)
- **Branches**: main (produccion), feature/* para desarrollo

## Decisiones arquitectonicas clave

| Decision | Razon |
|----------|-------|
| BLoC sobre Riverpod | Separacion eventos/estados mas explicita para flujo TTS complejo |
| GetIt sobre Provider DI | Acceso desde cualquier parte sin BuildContext |
| Drizzle ORM | Type-safe, migrations, compatible con edge |
| TtsRepositoryProxy | Hot-swap de implementacion TTS sin recrear BLoC |
| ElevenLabs eleven_multilingual_v2 | Mejor calidad en espanol con timestamps por caracter |
| SharedPreferences en web | Aceptado con documentacion de riesgo XSS (flutter_secure_storage no soporta web) |

## Estado actual (mayo 2026)

**Completado**: auth, import multi-formato, lector visual, TTS word-by-word, auto-scroll, responsive layouts, accesibilidad, auditoria de seguridad

**En progreso**: voces mas naturales (multi-provider TTS), voces por personaje

**Pendiente**: persistencia S3, Docker hardening, BFF para web, queue para TTS generation
