# LectorSync - Estado de desarrollo

Fecha: 2026-05-01

## Estado actual

Backend Fastify/TypeScript + frontend Flutter conectados, autenticación real con contraseñas, importación **EPUB + PDF + TXT + Markdown** end-to-end funcional, lector visual operativo, **TTS con sincronización palabra-a-palabra**, **auto-scroll al párrafo activo**, **ElevenLabs TTS**, **layouts responsivos desktop**, **microinteracciones desktop**, y **auditoría de accesibilidad**.

## Cambios implementados recientemente

### Multi-formato: PDF, TXT, Markdown (2026-05-01)

**Backend — sistema de parsers refactorizado:**
- `src/core/parsers/types.ts` — `ParsedChapter`, `ParsedBook` (con `fileFormat`), `BookParser` interface, `countWords()`
- `src/core/parsers/epub-parser.ts` — `EpubParser` (migrado del viejo `epub-parser.ts`, eliminado)
- `src/core/parsers/text-parser.ts` — `TextParser` (txt + md), detección de encoding (UTF-8 → latin1 fallback), splitting por headings/separadores, fallback por conteo de palabras (5000), stripping de sintaxis Markdown
- `src/core/parsers/pdf-parser.ts` — `PdfParser` con pdfjs-dist: outline → heurística de headings → fallback por páginas → fallback por conteo de palabras (4 niveles)
- `src/core/parsers/index.ts` — factory: `detectFormat()`, `isSupportedFormat()`, `createParser()`, `parseBookFile()`, mapas MIME/EXT para epub/pdf/txt/md
- `pdfjs-dist` instalado en backend
- `src/api/v1/routes.ts` actualizado: import usa `detectFormat` + `parseBookFile`, responses incluyen `file_format` y `total_words`

**Frontend — soporte multi-formato:**
- `Book` entity: enum `BookFormat` (epub/pdf/txt/md), campo `fileFormat`, getter `fileFormatLabel`
- `RemoteLibraryRepository`: `_contentTypeFor()` infiere MIME por extensión
- `library_page.dart`: file picker acepta `.epub`, `.pdf`, `.txt`, `.md`
- `BookCard`: badge de formato (pill con icono + label, color por formato)

### Layouts responsivos desktop (2026-05-01)

- `lib/core/layout/breakpoints.dart` — `LayoutBreakpoint` enum (compact <600, medium 600-1199, expanded ≥1200), helpers `breakpointOf()`, `gridCrossAxisCount()`, `when<T>()`
- `library_page.dart` — 3 layouts: compact (single-column), medium (sidebar 280px + grid 220px), expanded (NavigationRail + sidebar 320px + grid 240px)
- `reader_page.dart` — 3 layouts: compact (Drawer TOC), medium (AnimatedSize collapsible TOC 280px), expanded (collapsible TOC 320px + wider reader)
- Keyboard shortcuts: Space=play/pause, Left/Right=prev/next chapter, T=toggle TOC

### Microinteracciones desktop (2026-05-01)

- `BookCard` → `StatefulWidget` con `MouseRegion` + `AnimatedBuilder`: hover elevación (1→6) + scale (1.0→1.03), cursor `click`
- `_ContinueReadingHero` → `StatefulWidget` con `MouseRegion` + scale hover (1.0→1.02)
- `AnimatedSwitcher` en botón de tema (crossfade al ciclar light/dark/system)

### Accesibilidad (2026-05-01)

- `BookCard`: `Semantics(button: true, label: ...)` con título, autor, formato y progreso
- `_ChapterList`: indicador `trailing` con check icon en capítulo seleccionado
- Reader progress bar: `Semantics(label: 'Progreso del capítulo: X%')`
- Reader position slider: `Semantics(label: 'Posición de lectura: N de M palabras')`
- Voice menu: `Semantics(label: 'Menú de selección de voz')`
- System text scaling: respetado automáticamente por `Text`/`RichText` (no se anula)

### TTS con sincronización palabra-a-palabra (sesión anterior)

- Motor TTS: `flutter_tts ^4.2.5` + `ElevenLabsTtsProvider` (audio real con timestamps)
- Arquitectura: `TtsRepository` (interfaz) + `DeviceTtsRepository` + `AudioTtsRepository`
- Sincronización: `setProgressHandler` → búsqueda binaria → `wordIndexStream` → `ReaderBloc`
- Auto-scroll: `Scrollable.ensureVisible` al párrafo activo durante TTS
- Toggle play/stop: botón AppBar, menú de voz (device / ElevenLabs)
- Debounce de guardado: 700ms manual, 2s durante TTS

## Tests

- Backend `npm test` → **52/52 OK** (10 route + 35 parser + 7 TTS)
- Backend `npm run typecheck` → OK
- Frontend `flutter analyze` → 0 issues

## Cómo probar manualmente

1. `cd backend && npm run db:up && npm run dev`
2. `cd lectorsync && flutter run -d chrome` (o emulador)
3. Registrarse → entrar a la biblioteca
4. Botón **+** → seleccionar `.epub`, `.pdf`, `.txt` o `.md` → aparece card con badge de formato

## Pendientes ordenados por prioridad

| # | Pendiente | Notas |
|---|---|---|
| 1 | Revocación de refresh tokens en logout | Bajo |
| 2 | Persistencia del archivo original (`file_key` → S3/storage) | Hoy solo se guarda el texto extraído |
