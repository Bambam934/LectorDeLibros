# Empezar con LectorSync

*Última actualización: 2026-07-16*

App multiplataforma de lectura sincronizada con audio (TTS palabra-a-palabra) para Android, iOS, Web, Windows, macOS y Linux.

---

## Requisitos

- **Flutter** con Dart SDK `^3.11.5` (`flutter --version`).
- **Node.js 22+** y npm.
- **Docker** (para PostgreSQL local y el backend dockerizado).

## Arrancar en modo offline (lo más rápido)

La app arranca **sin backend** por defecto (`OFFLINE_MODE=true`). Login acepta cualquier credencial; los libros (PDF/TXT/MD) se guardan en el dispositivo.

```bash
cd lectorsync
flutter pub get
flutter run -d chrome        # o -d windows, o un emulador/dispositivo
```

## Arrancar en modo conectado (con backend)

```bash
# 1. Backend + Postgres con Docker
cd backend
cp .env.example .env         # completa JWT_SECRET y DATABASE_URL
docker compose up -d         # backend en :3000, Postgres en 127.0.0.1:5432

# (alternativa sin Docker para el backend)
npm install && npm run db:up && npm run dev

# 2. App apuntando al backend
cd ../lectorsync
flutter run --dart-define=OFFLINE_MODE=false --dart-define=API_BASE_URL=http://localhost:3000
```

En Android emulado, el host es `http://10.0.2.2:3000`; en un dispositivo físico, la IP LAN de tu máquina.

## Comandos de desarrollo

**Backend** (`cd backend`):
```bash
npm run dev        # Fastify con watch
npm test           # suite (tsx --test) — 61 tests
npm run typecheck  # tsc --noEmit
npm run db:studio  # explorar la DB
```

**Flutter** (`cd lectorsync`):
```bash
flutter analyze              # obligatorio antes de commit
flutter test                 # unit + widget — 123 tests
flutter build apk --release  # APK solo ARM firmado
flutter build web            # build web
```

## Estructura del proyecto

```
LectorDeLibros/
├── .claude/
│   ├── CLAUDE.md              ← contexto del proyecto
│   ├── agents/
│   │   └── lectorsync-expert.md   ← FUENTE DE VERDAD: arquitectura, reglas, aprendizajes
│   └── docs/                  ← esta documentación
├── backend/                   ← Fastify + Drizzle + PostgreSQL
│   ├── src/
│   │   ├── api/v1/routes.ts   ← todos los endpoints
│   │   ├── core/             ← auth, parsers, tts, realtime-bus, env
│   │   └── db/               ← schema Drizzle + migraciones
│   └── docker-compose.yml
├── lectorsync/                ← app Flutter
│   ├── lib/
│   │   ├── core/             ← di, network, router, storage, sync, theme
│   │   └── features/         ← auth, library, reader, settings (domain/data/presentation)
│   └── test/
└── lector_sync_project_definition.md   ← blueprint original
```

## Dónde mirar primero

1. **`.claude/agents/lectorsync-expert.md`** — la referencia más densa y actual: reglas de arquitectura, restricciones críticas y aprendizajes de campo del TTS que no están en el código.
2. **`.claude/docs/ARCHITECTURE.md`** — diagramas y flujos.
3. **`.claude/docs/BACKEND-API.md`** — endpoints.
4. **`.claude/docs/FLUTTER-GUIDELINES.md`** — convenciones de Dart/Flutter.
