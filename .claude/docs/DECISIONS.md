# Decisiones de Arquitectura de LectorSync (ADRs)

*Última actualización: 2026-10-03 · Estado: rama `desarrollo` · `main` estable*

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

**Reabierto el 2026-10-03 por el ADR 13**: en los PDF offline la detección pasa a la extracción (fuente y posición) y el capítulo guarda bloques tipados.

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
- **HTTP sin cifrar solo en debug** (2026-10-03): la configuración que lo permite hacia cualquier IP de la LAN vive en `android/app/src/debug/res/xml/network_security_config.xml`; la de `src/main` (release) solo lo admite hacia el emulador, `localhost` y `192.168.0.7`, y lo prohíbe explícitamente en el `base-config` porque en Android 7-8 el valor por defecto es permitirlo. Antes la permisiva viajaba en el APK de release: en modo conectado, la contraseña y el refresh token cruzaban la Wi-Fi en claro.

## 12. Modo concentración y lectura en segundo plano (2026-10-03)

Diseñado con `/diseñar` y aprobado por secciones. Dos funciones que comparten una pieza: un único controlador decide a partir de la misma señal, *si la voz está sonando*.

**Modo concentración** (`features/reader/presentation/reading_focus_controller.dart`): pantalla completa de verdad y, donde se puede, el "No molestar" del sistema.

- **Se entra explícitamente**: botón en la barra (menú ⋮ en el móvil) o F11; se sale con el mismo botón, Atrás, Esc, F11 o cerrando el libro. El toque sobre el texto sigue alternando solo los controles del lector: colgar de ahí el silencio lo encendería y apagaría con cada toque. No se recuerda entre sesiones.
- **Regla única**: `silencio = pantalla completa ∧ (app visible ∨ voz sonando)`. El silencio sigue con la pantalla apagada mientras la voz lee; se quita al pausarla (con 3 s de margen, para que pasar de capítulo no lo quite y lo vuelva a poner), al salir o al cerrar el libro. Quitarlo nunca depende de que algo salga bien: el estado se marca apagado antes de pedírselo al sistema.
- **Android 10+**: una `AutomaticZenRule` propia ("Lectura (LectorSync)", `ReadingQuietMode.kt`) con filtro PRIORITY —pasan las excepciones del usuario— y `ZenPolicy.allowMedia(true)`, porque si no silenciaría la propia voz. Permiso "Acceso a No molestar" explicado la primera vez, con "No volver a preguntar". **Descartado el filtro global** (`setInterruptionFilter`): al salir apagaba también los modos automáticos del usuario que hubieran empezado entretanto, se quedaba puesto si la app moría y cambia de comportamiento con targetSdk ≥ 35.
- **Red de seguridad**: la regla se apaga al arrancar cada proceso, desde `MainActivity.kt` y no desde Dart: el motor de audio_service ejecuta `main()` antes de que la actividad registre el canal, y la llamada desde Dart se perdería en silencio. **Descartado el temporizador de seguridad** (alarma que apaga la regla aunque la app muera): solo cubre una caída en primer plano, y el icono de No molestar queda a la vista en ese caso.
- **Windows**: no hay API soportada (`FocusSessionManager` exige un token que concede Microsoft). La pantalla completa la pone `window_manager` y un aviso único lleva a la regla nativa de Windows "Activar No molestar al usar una app en pantalla completa". **iOS y web**: solo pantalla completa (no hay API pública). macOS y Linux no tienen carpeta en el repo.
- **Límite conocido**: en Android 15+ la regla copia las excepciones al crearse y puede no coincidir del todo con las del usuario; se ajusta editando el modo en Ajustes. En Android 10-14 hereda las del usuario en vivo.

**Lectura en segundo plano** (`features/reader/presentation/background/reading_audio_handler.dart`): la voz sigue con la pantalla apagada o en otra app, como un audiolibro.

- **audio_service**: servicio de reproducción en primer plano con notificación "Leyendo · título", controles en la pantalla de bloqueo y en los auriculares. Es lo que impide que Android duerma la CPU entre frases o cierre la app. **Descartado "solo no pararla"** (quitar la parada en `paused`): Android cortaría la lectura a los pocos minutos. **Descartado un servicio propio en Kotlin**: más código nativo propio y sin controles de medios.
- **`androidStopForegroundOnPause: true` con 5 s de margen** (corregido el 2026-10-03 con el visto bueno del usuario). La desviación anterior —quedarse en primer plano también en pausa— retenía el wakelock de audio_service: medido en un Pixel 10 Pro XL con Android 17, 12 minutos tomado con la voz parada. Y como el servicio sigue enlazado (la propia app y la IU del sistema), ni cerrar el libro ni la ✕ lo soltaban. Ahora la pausa sale de primer plano, suelta el wakelock y deja la notificación descartable; cerrar el libro o la ✕ la retiran. Las paradas de la voz se publican con margen para que el salto de capítulo con la pantalla apagada no saque al servicio de primer plano, porque volver desde segundo plano lanza `ForegroundServiceStartNotAllowedException` salvo justo después de un botón multimedia. La pausa desde la notificación es inmediata, y el play desde ella se publica antes de que arranque la voz.
- **audio_session**: pausa al desconectar los auriculares o con una llamada; no con un aviso que solo baja el volumen (`duck`). No se reanuda sola. El foco de audio solo se pide mientras la voz suena.
- **Si el servicio no arranca** (cualquier plataforma que no sea Android, o un fallo), no se registra y el lector vuelve a parar la voz en segundo plano: nunca queda a medio funcionar.

Pendiente de verificar en dispositivo (no hay pruebas automáticas posibles): todo lo que toca el sistema —icono de No molestar, notificaciones silenciadas, voz audible con la regla puesta, lectura de más de 10 minutos con la pantalla apagada cruzando capítulos, controles de bloqueo y auriculares, pausa con llamadas y al desconectar los auriculares— y en Windows, entrar y salir de pantalla completa sin los fallos conocidos de `window_manager`.

## 13. Bloques tipados por maquetación en los PDF offline (diseño aprobado 2026-10-03, implementado 2026-10-04, pendiente de verificar en el móvil)

Reabre el §7, que evitó a propósito tocar la extracción, la entidad `Chapter` y la caché. Medido en los libros reales del usuario: en "Cálculo integral" las ecuaciones son dibujos vectoriales (página 136: huecos entre líneas sin texto ni imágenes; las fuentes matemáticas son el 1,5 % del texto) y la app se las salta sin avisar, mientras enmarca teléfonos como fórmulas. En "Ciencia de datos desde cero" el código va en LiberationMono (30 % de los caracteres) y su sangría se recupera por la posición.

- **Detección en la extracción, solo en modo offline**: `extractTextLines` (fuente, tamaño y posición; `repairSurrogates` sobre cada línea) dentro del isolate. La fuente de cuerpo es la de más caracteres. Por línea: cabecera o pie (franja del margen y repetición en ≥ 3 páginas), código (la mayoría de sus palabras en monoespaciada; sangría por la posición), título (otra familia o más tamaño, línea corta y separada) y cuerpo, unido en párrafos por la sangría de primera línea, los huecos y los guiones. **Plan B por libro**: sin una fuente de cuerpo clara (< 40 % de los caracteres), el proceso actual.
- **Ecuaciones y figuras**: un hueco vertical de más de ~2 interlineados entre líneas de la misma página, **validado pintándolo en miniatura con pdfrx** (sin esa comprobación se inventarían fórmulas en huecos vacíos). Se muestran recortadas del PDF: hasta ~4 líneas son "Fórmula"; más altas, "Figura".
- **Modelo**: `Chapter` con bloques (párrafo, título, código y figura con página y rectángulo). Las palabras siguen siendo la única referencia de progreso, resaltado y voz: la figura aporta una palabra marcadora y el código cuenta las suyas aunque la voz lo salte. Caché v6. Sin bloques (servidor, cachés viejas), el comportamiento actual.
- **Pantalla**: título destacado; código en monoespaciada sin partir líneas, con desplazamiento horizontal; figura recortada al ancho de la columna, invertida en los temas oscuros solo si es una fórmula. "Ver en el libro" va directo a su página.
- **Voz**: el título con pausa; el código según el ajuste "Leer los bloques de código en voz alta" (por defecto avisa "Bloque de código." y lo salta); la figura dice "Fórmula." o "Figura.".
- **Markdown**: las vallas pasan a bloques de código y los `###`, a títulos. **TXT**, como hoy, con una regla más para no tomar teléfonos por fórmulas.
- **Descartados**: afinar las heurísticas de texto (no recuperan las ecuaciones vectoriales ni la sangría); un modo página (sin reflujo, inutilizable en el móvil; queda como posible complemento); el servidor y los EPUB ahora (pendientes con la fase 1 de contenido rico); copiar código, resaltado de sintaxis, código en línea en monoespaciada y capítulos por títulos (YAGNI).
- **Implementación (2026-10-04)**: `data/parsing/pdf_layout.dart` (clasificador puro), `ink_probe.dart`, `markdown_blocks.dart`; `splitByBlocks` en `tts_segmentation.dart`; widgets en `reader_page.dart` y `pdf_crop_image.dart`. Hallado al medir los libros con Syncfusion, y resuelto sin cambiar el diseño:
  - el extractor de líneas corta una línea visual cada vez que cambia la altura del glifo (código en línea, versalitas, exponentes): se reagrupan los trozos por solape vertical;
  - en "Cálculo integral" `fontSize` vale 1,0: el tamaño sale de la altura del rectángulo;
  - la variable en cursiva va pegada y en otra fuente ("subíndicex"): el cambio de fuente separa palabras, salvo en un exponente;
  - los glifos que no traduce salen con su código decimal (la ligadura "fi" de Minion es "super31cie"), mientras `extractText` sí los traduce: se aprende la traducción cotejando con el texto plano las seis páginas con más palabras sospechosas, con la palabra vecina como contexto;
  - el borde de un recuadro ("Nota:") tiene tinta: se exige tinta dentro de la caja, sin las filas que la cruzan ni sus columnas del borde;
  - la cabecera se busca solo por encima de donde empieza el texto en una página típica, para no tomar por cabecera un "Ejercicio 2" al principio de varias páginas.
- **Cambio respecto al diseño (no forzoso, pendiente del visto bueno del usuario)**: las fórmulas no se invierten en los temas oscuros y sepia, sino que toman el color del texto sobre fondo transparente en todas las paletas. En sepia, invertir pondría un recuadro negro sobre la página clara. Las figuras se pintan a la escala de la letra, no estiradas al ancho de la columna.
- **Medido en el PC** (primera apertura): "Cálculo integral" 13,5 s de maquetación (lo mismo que costaba `extractText`) más 1,5 s de tinta, con 358 fórmulas y 132 figuras; "Ciencia de datos desde cero" 11,7 s más 1,3 s.
