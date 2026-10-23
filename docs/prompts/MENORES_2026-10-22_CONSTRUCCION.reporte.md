# Reporte: MENORES_2026-10-22

**Constructor: Claude.** Antigravity no tiene línea de comandos para recibir el encargo, y el usuario pidió hacerlo directamente. Se usaron el mismo encargo, la misma rama y el mismo formato de reporte.

## Commits

- `e28bf2d` fix(parsers): decodificar los TXT en ANSI como Windows-1252 y quitar el BOM — P1 (incluye el comentario de CA-6)
- `75db8ac` chore(deps): quitar @types/adm-zip, que sobra — P2
- `0098a16` fix(library): rechazar al importar offline los libros de más de 50 MB — P3

## Criterios de aceptación

- CA-1: CUMPLE — test `decodes a non-UTF-8 TXT as Windows-1252, not Latin-1` (`backend/src/core/parsers/parsers.test.ts:100`); decodificación en `backend/src/core/parsers/text-parser.ts:42` y `:148`.
- CA-2: CUMPLE — test `strips the UTF-8 BOM from the text and the title` (`parsers.test.ts:114`).
- CA-3: CUMPLE — test `keeps UTF-8 without BOM unchanged` (`parsers.test.ts:122`) y los tests previos del `TextParser` siguen pasando.
- CA-4: CUMPLE — `@types/adm-zip` fuera de `backend/package.json`; `npm run typecheck` limpio.
- CA-5: CUMPLE — tests de `lectorsync/test/features/library/data/repositories/local_library_repository_test.dart:20` (rechazo con `FileFailure` y catálogo vacío) y `:38` (50 MiB exactos no se rechazan por tamaño); comprobación en `local_library_repository.dart:61`.
- CA-6: CUMPLE — `lectorsync/lib/features/reader/data/parsing/text_decoding.dart:9` dice ahora «El backend decodifica igual».

## Pruebas

- npm test: 96 pasan / 0 fallan
- npm run typecheck: limpio
- flutter analyze: limpio («No issues found!»)
- flutter test: 345 pasan / 0 fallan
- Comprobaciones con el buscador:
  - `ENCODING_FALLBACK = 'latin1'` ya no está en `backend/src`; `'latin1'` solo aparece en los datos del test nuevo (`parsers.test.ts:103-107`).
  - `@types/adm-zip` ya no está en `backend/package.json`.
  - `Latin-1` ya no aparece como lo que hace el backend en el comentario de `decodeTextBytes`; solo como término de comparación (`text_decoding.dart:10`).

## Archivos tocados

- `backend/package-lock.json`
- `backend/package.json`
- `backend/src/core/parsers/parsers.test.ts`
- `backend/src/core/parsers/text-parser.ts`
- `lectorsync/lib/features/library/data/repositories/local_library_repository.dart`
- `lectorsync/lib/features/reader/data/parsing/text_decoding.dart`
- `lectorsync/test/features/library/data/repositories/local_library_repository_test.dart`

## Afirmaciones retiradas

- Ninguna.

## Dudas

- P1 permitía `new TextDecoder('windows-1252')`. Se comprobó que en Node decodifica como Latin-1 (0x80 → U+0080), así que se usa una tabla propia igual a la del cliente.
- `npm uninstall` avisó de vulnerabilidades que ya existían; no se ejecutó `npm audit fix` (prohibido por el encargo).
- La comprobación de CA-6 del encargo («`Latin-1` ya no aparece en el comentario») se cumple en su intención, pero el literal sigue en la línea 10 como comparación («Windows-1252 coincide con Latin-1 en todas las letras»).
