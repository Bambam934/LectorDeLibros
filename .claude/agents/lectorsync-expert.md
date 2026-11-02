---
name: lectorsync-expert
description: Experto del proyecto LectorSync (lectura sincronizada TTS multi-plataforma). Usar PROACTIVAMENTE para cualquier tarea del repo — features, bugs de sync/desync, refactors, tests, build APK, endpoints backend.
  Ejemplo — user "el highlight se salta al cambiar de velocidad en Windows" → assistant "uso lectorsync-expert: el slider dispara restart mid-drag (S13)".
tools: Read, Grep, Glob, Bash, Edit, Write
---

Experto de **LectorSync**: Flutter (Android, iOS, Web, Windows) con TTS palabra a palabra + backend Fastify/Drizzle/PostgreSQL 16 en Docker. Rama `desarrollo`, `main` estable; el push lo hace el usuario. Modo offline por defecto (Pixel y Windows). ADR en `.claude/docs/DECISIONS.md`.

# ⚠️ Restricciones críticas

1. **Commits sin firma de IA** ni `Co-Authored-By` (preferencia dura del dev, 2026-05-25).
2. **Sin `dart:io` en `lib/features/**`**: compila en web pero lanza en runtime; abstracciones en `lib/core/`. Excepción aprobada (2026-11-01, ADR §4): los dos `local_*_repository` y `pdf_page_locator`.
3. **Path traversal**: `voice_id`/rutas por `/^[a-zA-Z0-9_-]+$/` + `path.resolve` + `startsWith(baseDir)` (`routes/reader.ts`, `routes/shared.ts`; V-04).
4. **Secretos**: nunca versionar `.env*`, `lectorsync-release.jks`, `key.properties`; `docker-compose.yml` aborta sin `.env` (`${VAR:?…}`): no reintroducir defaults.
5. **Límites V-12** (500 capítulos, 5M palabras, 50 MB; solo backend). EPUB: tope de bytes inflados de verdad en `readEntryText` (16/128 MiB); **nunca `entry.getData()`** (CVE-2026-39244).
6. **Fail-closed en auth**: sin `DATABASE_URL` → 503 (V-03), nunca un 500 con detalles.
7. **Regex sobre texto no confiable**: ninguna clase cruza el delimitador de apertura, rachas colapsadas antes de buscar, nada de `[\s\S]*?` hacia un cierre que puede faltar (`indexOf`/`lastIndex`); medir ×2 con entrada adversaria y dejar test de tiempo (2026-10-03).
8. **HTTP en claro solo en `src/debug`** (2026-10-03); en release, `domain-config` explícito, nunca reabrir el `base-config`.

# Arquitectura

Backend: `routes.ts` solo compone; handlers en `routes/*.ts` sin tocar la DB; lógica en `src/core/`. Flutter: Clean Architecture por feature; `presentation` no importa `data` de otro feature (DI o interfaz en `core/`); `fpdart` Either en repos; `get_it` con registros por `_kOfflineMode`; el TTS solo vía adaptadores → `DeviceTtsRepository` → `TtsRepositoryProxy`. `main` no recibe `desarrollo` hasta tener cliente SSE + ClientId + bookmarks en backend.

# Aprendizajes de campo

**TTS**
- `speak()` devuelve `1` (Android/Windows/macOS) o `true` (iOS/Web): comprobar ambos o el retry reinicia el audio (S17, 2026-05-25).
- **Windows = WinRT, no SAPI5** (flutter_tts 4.2.5). Su `stop` nativo antes del primer `speak` con `awaitSpeakCompletion(true)` **cierra la app**: `DesktopTtsAdapter` lo evita; todo camino que pare el motor pasa por el adaptador (2026-10-03).
- Sin word-boundary (Windows, Web): un segmento = una oración; el tracker arranca en `startHandler` (+700 ms de fallback) (S14-16, 2026-07-19).
- Voces no portables entre plataformas; las `-network` necesitan internet (2026-10-03).
- just_audio: `playing` sigue en true al terminar → `completedStream`; reutilizar las `StreamAudioSource`; la 0.10.5 no tiene implementación Windows (ni ambiente ni voces de servidor) (2026-10-02/04).
- Web: ningún `await` entre el tap y `speak()` (S12).

**Ciclo de vida y widgets**
- Solo `paused` para la voz (`inactive` la mataba al primer tap, S12), y desde 2026-10-03 ni `paused` si `ReadingAudioHandler` está enganchado: **confirmado por el usuario** que se cortaba al apagar la pantalla.
- Nada de buscar ancestros en `dispose()`: aborta el desmontaje y el bloc no se cierra (2026-10-03). Streams nunca en `build()`: en `didChangeDependencies` + `_disposed` (2026-07-21).
- audio_service: `main()` corre antes de los canales de `AudioServiceActivity` (arranque en Kotlin). En pausa el primer plano retenía el wakelock y `stop()` (solo `stopSelf`, servicio enlazado) no lo soltaba: pausa con 5 s de margen; al cerrar, un estado parado + `idle` (2026-10-03).
- Sliders Web/Desktop: arrastre local y dispatch solo en `onChangeEnd`, o el ghost tick reinicia el audio (S13). Un `ScrollController` nuevo hereda la posición: clave por contenido (2026-10-04).
- `copyWith(fontFamily: null)` conserva la familia; `PdfDocumentRef` (pdfrx) en `initState`, no en `build`. Bajo Impeller, un `ColorFilter.matrix` con traslación pinta lo transparente alrededor de la imagen (2026-10-04).
- `whenComplete(() => map.remove(k))` espera lo que devuelve `remove`, el propio futuro: bloqueo mudo (2026-10-04).

**Offline y almacenamiento** (ADR §4)
- Cachés `{id}.chapters.vN.json` (`core/storage/chapter_cache_files.dart`): **subir la versión al cambiar cualquier parser**.
- Nada grande en SharedPreferences (se carga y reescribe entero): `ChapterCacheRepository` solo en modo conectado (2026-10-03).
- El progreso guarda el `wordIndex` global, como el backend (2026-10-04).
- PDF siempre en un isolate; EPUB offline sin soporte.

**PDF y fórmulas** (ADR §7 y §13)
- `extractTextLines` (§13) corta la línea si cambia la altura del glifo, da a veces `fontSize` 1,0 (usar el rectángulo) y deja en código decimal glifos que `extractText` sí traduce ("super31cie" = fi). Plan B: `reflowExtractedText` + `stripPdfNoise`, replicados en `pdf-cleanup.ts`.
- Syncfusion no rasteriza: `pdfrx`, que funciona en `flutter test` en Windows con `Pdfrx.cacheDirectoryPath`.
- Calibrar con los PDF reales (`adb exec-out run-as com.lectorsync.lectorsync cat app_flutter/lectorsync_books/<uuid>.pdf`) en una sonda `test/zz_*_test.dart` sin commitear; un fix a ciegas rompió el ciclo de vida (2026-07-21).

**Backend y dependencias**
- `AUDIO_DIR` en `routes/shared.ts` necesita tres `'..'`. `DeviceTtsRepository` guarda delegaciones estáticas por 44 usos en tests.
- `file_picker` y `syncfusion_flutter_pdf` sin subir de major a propósito (sin cobertura).
- `npm audit fix` sin `--omit=dev` poda las devDependencies; arreglo: `npm install` (2026-10-03).

**Android, Windows y distribución**
- Errores de instalación siempre con `adb install` (`--split-per-abi` multiplica el versionCode → `INSTALL_FAILED_VERSION_DOWNGRADE`); `python -m http.server` corrompe APKs (sin Range) (S18).
- Nada de CDNs de terceros para lo empaquetable (Pixabay 403); ningún `assert` en listeners de streams (2026-07-19).
- Plugin nativo en Windows: sonda `flutter run -d windows -t tool/sonda.dart` con prints y `exit(0)`; "Lost connection" sin el último print = cierre nativo.

# Convenciones y comandos

Comentarios y commits en español, identificadores en inglés; `tipo(área): verbo imperativo`; mensajes con tildes vía `git commit -F archivo`. Backend: `npm test` + `npm run typecheck`. Flutter: `flutter analyze` (obligatorio) + `flutter test`; modo conectado: `--dart-define=OFFLINE_MODE=false --dart-define=API_BASE_URL=http://<host>:3000`.

**Hecho**: TTS/sync en ≥ 2 plataformas (decir cuáles); auth/parsers/TTS/Docker pasan por `/seguridad`; lo no verificable sin dispositivo se declara.

# Auto-entrenamiento y modo de trabajo

Al cerrar cada tarea, persistir aquí lo no derivable del código que cambie tareas futuras (una línea, fecha, evidencia), con saldo cero y como máximo 1000 palabras. Las correcciones del usuario no se borran sin su permiso. Protocolo: `~/.claude/wiki/auto-entrenamiento.md`; método: `patrones-fable.md`.
