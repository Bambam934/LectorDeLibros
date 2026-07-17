# Decisiones de Arquitectura de LectorSync (ADRs)

*Última actualización: 2026-07-16 · Estado: rama `desarrollo` (WIP sync multi-dispositivo) · `main` estable*

Este documento registra las decisiones técnicas vigentes y por qué se tomaron. Para el estado detallado de features y la bitácora de sesiones, ver la memoria del proyecto (`~/.claude/projects/.../memory/project_state.md`) y el agente `.claude/agents/lectorsync-expert.md`.

---

## 1. Stack backend

- **Framework**: Fastify 5 (Node.js, ESM). Alto rendimiento y ecosistema de plugins.
- **Lenguaje**: TypeScript 5.7 en modo `strict` + `noUncheckedIndexedAccess`.
- **ORM**: Drizzle ORM 0.45 — SQL type-safe con migraciones versionadas en `drizzle/`.
- **Base de datos**: PostgreSQL 16 (Docker en local; hostname interno `postgres`).
- **Validación**: Zod en todo input HTTP y en `core/env.ts`.
- **Hashing de contraseñas**: `scrypt` + `timingSafeEqual` de `node:crypto` (NO bcrypt). Ver `core/password.ts`.
- **Auth**: JWT access (15 min) + refresh (30 días) con rotación y revocación bidireccional.

## 2. Stack frontend (móvil/desktop/web)

- **Framework**: Flutter (Dart SDK `^3.11.5`).
- **Gestión de estado**: `flutter_bloc` 9 — BLoC para flujos complejos (sincronización audio/texto), Cubit para simples (auth, tema, preferencias). Elegido sobre Riverpod por separación explícita evento/estado.
- **Ruteo**: `go_router` 17 declarativo con guard de autenticación.
- **Inyección de dependencias**: `get_it` 9 (`core/di/injection_container.dart`). Elegido sobre Provider para acceso sin `BuildContext`.
- **HTTP**: `dio` 5 con interceptor global (inyecta JWT, refresca en 401, añade `X-Client-Id`).
- **Almacenamiento seguro**: `flutter_secure_storage` 10 (Keychain/Keystore en móvil, IndexedDB cifrado en web).
- **Programación funcional**: `fpdart` 1.2 — `Either<Failure, T>` en toda operación de repositorio.

## 3. Arquitectura de la app (Clean Architecture)

Ambos lados siguen capas `domain → data → presentation`. Estructura real por feature:

```
lib/features/<feature>/
├── domain/        # entities, repositories (abstractos), usecases
├── data/          # repositories (concretos), datasources, models
└── presentation/  # bloc|cubit, pages, widgets
```

Features actuales: `auth`, `library`, `reader`, `settings`. Infraestructura compartida en `lib/core/` (`di`, `network`, `router`, `storage`, `sync`, `theme`, `utils`, `errors`, `layout`, `constants`).

**Regla dura**: `presentation` nunca importa `data` de otro feature; la composición pasa por `injection_container.dart`. (Deuda conocida 2026-07-16: `reader.data` importa `library.data` en el modo offline — ver `project_state`/agente, remediación pendiente vía `filePathOf` en la interfaz.)

## 4. Modo offline (2026-06-09)

Flag compile-time `OFFLINE_MODE` (`bool.fromEnvironment`, **default `true`** mientras no haya servidor desplegado). En `true` la app no depende del backend:

- `LocalAuthRepository` — acepta cualquier credencial no vacía.
- `LocalLibraryRepository` — archivos en el sandbox (`path_provider`) + catálogo JSON en `SharedPreferences`.
- `LocalReaderRepository` — parsea PDF (Syncfusion), TXT (por "Capítulo X") y MD (por headers). **EPUB no soportado offline aún.**

Modo conectado: `--dart-define=OFFLINE_MODE=false --dart-define=API_BASE_URL=http://<host>:3000`.

## 5. Arquitectura de TTS

- **`TtsRepositoryProxy`** — hot-swap en runtime entre TTS de dispositivo y audio externo sin recrear el BLoC.
- **`DeviceTtsRepository`** — `flutter_tts` nativo, gratuito, voces en español prioritarias.
- **`AudioTtsRepository`** — audio pregenerado (ElevenLabs) reproducido con `just_audio`.
- **Adapters por plataforma**: `NativeMobileTtsAdapter` (Android/iOS), `WebTtsAdapter` (navegador), `DesktopTtsAdapter` (Windows/macOS/Linux) — encapsulan las diferencias de word-boundary por plataforma.
- **`SegmentProgressTracker`** — estima el índice de palabra cuando la plataforma no emite word-boundary (Web/Desktop); se calibra por `(plataforma, voz)` y persiste en `SharedPreferences`. En plataformas sin word-boundary se segmenta **por oración** para evitar drift acumulado. Ver el agente para los aprendizajes de campo del pipeline TTS.

## 6. Sincronización multi-dispositivo (WIP en `desarrollo`)

- **Transporte**: Server-Sent Events (SSE) en `GET /api/v1/sync/stream`, no WebSockets — unidireccional server→cliente, más simple y compatible con `EventSource` del navegador.
- **`realtime-bus.ts`** — bus en memoria que hace fan-out de eventos de progreso por usuario.
- **`X-Client-Id`** — cada dispositivo genera un UUID estable; el push SSE de una escritura se etiqueta con su originador para que ese mismo dispositivo descarte el eco en vez de re-aplicarlo.
- **Cliente Flutter**: `core/sync/sync_stream_client_{io,web,stub}.dart` — implementación condicional por plataforma (patrón a replicar para cualquier código con `dart:io`).

## 7. Temas (Material 3)

Uso estricto de `ColorScheme` (`surface`, nunca la deprecada `background`). Modos: system, light, dark, warm (sepia/ámbar, reduce luz azul) y scheduled (oscuro 20:00–07:00). Ver `core/theme/`.

## 8. Distribución

- **Backend**: Docker multi-stage (`node:22-alpine`, usuario no-root, healthcheck) + `docker-compose.yml` (backend en `:3000` a LAN, Postgres solo en `127.0.0.1`).
- **Android**: APK universal firmado (keystore propio gitignored). Diagnóstico de instalación siempre con `adb install` — el instalador gráfico oculta el error real (ver agente, Session 18).
