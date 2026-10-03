# Decisiones de Arquitectura de LectorSync (ADRs)

*Última actualización: 2026-08-11 · Estado: rama `desarrollo` · `main` estable*

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

**Regla dura**: `presentation` nunca importa `data` de otro feature; la composición pasa por `injection_container.dart`.

La deuda de 2026-07-16 (`reader` importaba `library.data` en modo offline) está saldada: `core/storage/local_book_store.dart` define el contrato `LocalBookStore` y `LocalLibraryRepository` lo implementa. Desde 2026-08-11 está además **registrado en GetIt** por ese contrato, no solo por su clase concreta, para que la UI del lector pueda resolver la ruta del archivo original sin conocer la capa `data` de `library`.

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

## 7. Contenido enriquecido: fórmulas en PDF (2026-08-11)

Extraer texto de un PDF de matemáticas aplana las ecuaciones: una integral acaba siendo `10.50.5(1)2+1=`. Ningún filtro de texto lo arregla — la información de maquetación ya no está.

- **`data/parsing/formula_detector.dart`** — heurística pura que distingue fórmula de prosa por densidad de símbolos y ausencia de palabras reales. Deliberadamente conservadora: ante la duda dice que no, porque marcar prosa como fórmula haría que el lector se saltase contenido real.
- **La unidad de detección es el PÁRRAFO, en los dos lados.** La heurística mide proporciones del bloque entero, así que solo significa algo sobre un párrafo. La UI ya lo hacía; el TTS no, y por eso `splitIsolatingFormulas()` (en `tts_segmentation.dart`) aísla cada párrafo-fórmula en su propio segmento **antes** de trocear la prosa. Corriéndola sobre la salida de `splitIntoSegments` (bloques de 200 palabras) o de `splitIntoSentences` (oraciones ya fusionadas con su vecina) no se disparaba nunca: la pantalla pintaba el recuadro y la voz leía la ecuación aplanada igual. La prosa se sigue segmentando de una pieza — en Android/iOS cada utterance extra cuesta 50-100 ms — y un capítulo sin fórmulas delega directo, sin cambio de comportamiento.
- **Al leer**: `muteFormulaSegments()` sustituye el texto hablado por "Fórmula." y marca el segmento con `isFormula`. **Conserva `words` y `globalStartWordIndex`**, así que el seguidor de palabras sigue cayendo donde debe; solo cambia el ritmo dentro del bloque. La marca es necesaria porque la recuperación tras un utterance interrumpido rehace el texto desde `words`, y sin ella devolvía la ecuación que el aviso vino a sustituir.
- **Al mostrar**: el párrafo se centra, va en monoespaciada y con filete lateral, sin justificar ni sangrar (justificar una tira de símbolos es justo lo que la vuelve ilegible). La familia va **explícita** (`fontFamily: 'monospace'`): `TextStyle.copyWith` resuelve cada campo como `valor ?? this.valor`, así que pasar `null` conservaba la fuente de lectura.
- **Al pulsar "Ver en el libro"**: se renderiza la página original con `pdfrx` (PDFium). La página se localiza **en el momento de pulsar**, buscando el texto en el PDF (`PdfPageLocator`), en vez de arrastrar el número de página por el pipeline de parseo: así no hubo que tocar la extracción, ni la entidad `Chapter`, ni migrar la caché de capítulos ya generada en los dispositivos. El índice se construye **en un isolate** (Syncfusion extrae página a página de forma síncrona: en el hilo de UI son segundos de congelación y ANR en Android) y la comparación normaliza espacios, mayúsculas **y guiones**, porque el fragmento del capítulo ya pasó por el reflow que une las palabras partidas y el PDF crudo conserva ese guion.

`syncfusion_flutter_pdf` se queda para extraer texto; **no sabe rasterizar**, y por eso entró `pdfrx`.

## 8. Sonidos ambientales (2026-08-11)

Los cinco presets apuntaban al CDN de Pixabay, que bloquea el hotlinking: los cinco devolvían HTTP 403 y la app culpaba a la conexión del usuario.

- **Ruidos sintetizados en el dispositivo** (`data/audio/ambient_noise_synth.dart`): lluvia, chimenea, oleaje, ruido rosa y blanco. Sin red, sin licencias, sin peso en el APK. Se sirven desde memoria con `StreamAudioSource` y no como fichero, porque `dart:io` y `path_provider` no existen en web.
- **Una instancia de `SynthAudioSource` por perfil, reutilizada.** just_audio registra cada `StreamAudioSource` en el mapa interno de su proxy HTTP y **nunca la desregistra**: crear una instancia por cambio de preset dejaba el WAV anterior (1,68 MB) retenido para siempre. Reutilizarla acota el coste a una entrada por perfil realmente reproducido.
- **Solo se precarga si va a sonar.** `restorePreferences()` cargaba la fuente siempre y el `if (enabled)` gobernaba únicamente el `play()`; como `stop()` persiste `enabled=false` pero no borra el id del preset, cada arranque en frío renderizaba 20 s de audio en un isolate para algo que estaba apagado.
- **Grabaciones** para lo que no es ruido estacionario (cafetería, bosque): MP3 en `assets/audio/`, dominio público, créditos en `assets/audio/CREDITS.md`. **Nunca Ogg Vorbis**: no suena en iOS ni macOS.

## 9. Tipografía del lector (2026-08-11)

Las reglas viven en `features/reader/presentation/reading_typography.dart` como **funciones puras**, no como números sueltos dentro de un `build()`: así se pueden fijar con tests y no se cambian por accidente.

- **Sin justificar por defecto.** Flutter no tiene guionado automático, y justificar reparte el sobrante entre los espacios: en la columna de un móvil (~45 caracteres) salen huecos enormes y ríos de blanco. La preferencia `justifyText` existe y se respeta para quien la quiera — pero antes se **ignoraba**: el lector tenía `TextAlign.justify` clavado y el interruptor del panel no hacía nada.
- **Medida de línea de ~66 caracteres**: `maxColumnWidth` por defecto pasa de 720 px (~80 caracteres, obliga a buscar el arranque de cada línea) a 600 px (~67, la medida clásica).
- **Sangría proporcional** (1,2 em) en vez de 24 px fijos, que se notaban con cuerpo de 14 px y desaparecían con 32.
- **El primer párrafo del capítulo no se sangra**: la sangría significa "empieza otro párrafo" y tras un título no hay ninguno anterior del que separarse.
- **Jerarquía del encabezado derivada del cuerpo** (número ×1,6, título ×1,25) en vez de tamaños fijos: con 28/20 clavados, subir el cuerpo a 32 px dejaba el título más pequeño que el texto que encabeza.

Los defaults nuevos solo alcanzan a quien no haya tocado el panel: `save()` persiste todos los campos a la vez, así que una instalación con ajustes previos conserva los suyos.

## 10. Temas (Material 3)

Uso estricto de `ColorScheme` (`surface`, nunca la deprecada `background`). Modos: system, light, dark, warm (sepia/ámbar, reduce luz azul) y scheduled (oscuro 20:00–07:00). Ver `core/theme/`.

## 11. Distribución

- **Backend**: Docker multi-stage (`node:22-alpine`, usuario no-root, healthcheck) + `docker-compose.yml` (backend en `:3000` a LAN, Postgres solo en `127.0.0.1`).
- **Android**: APK universal firmado (keystore propio gitignored). Diagnóstico de instalación siempre con `adb install` — el instalador gráfico oculta el error real (ver agente, Session 18).
