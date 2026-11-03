# Plan: bloques tipados por maquetación en los PDF offline (ADR 13)

*Diseño aprobado el 2026-10-03 con `/diseñar` (sesión 24), sección a sección. **Implementado el 2026-10-04** (`65eefbc`, `7bed6c4`, `3505ebe`, `98bac22`): pasos 1 a 10 hechos. Verificado en el Pixel el mismo día, con siete arreglos (`21c5f99`..`e40c3ec`); falta el ajuste de leer el código y una prueba más larga en Windows. Lo hallado al implementar y al verificar está en el ADR 13.*

## Objetivo

En los PDF del modo offline:

- el código se ve con formato propio;
- las ecuaciones y los ejercicios se detectan de verdad, en lugar de adivinarlos por el texto aplanado.

Origen: dos peticiones del usuario el 2026-10-03, el formato especial para libros con código y la mejor detección de ecuaciones y ejercicios matemáticos.

## Decisiones del usuario

1. **Alcance:** ecuaciones y ejercicios **y** código, a la vez.
2. **Voz ante el código:** lo decide el usuario con un ajuste. Por defecto, "avisar y saltar".
3. **Dónde:** solo en modo offline. La paridad del servidor y los EPUB van con la fase 1 de contenido rico (diseño aprobado el 2026-07-19).
4. **Enfoque B:** maquetación más bloques tipados. Reabre el ADR §7, que evitó a propósito tocar la extracción, la entidad `Chapter` y la caché.
5. **Secciones 1 a 5:** aprobadas tal como se describen abajo.

**Descartados**, con su porqué (también en el ADR 13):

| Opción descartada | Motivo |
| --- | --- |
| Afinar las heurísticas de texto (enfoque A) | Las ecuaciones vectoriales ya no existen en el texto extraído, y la sangría del código se pierde en el reflujo. |
| Modo página (enfoque C) | Sin reflujo, no se puede usar en el móvil. Queda como posible complemento para tablet u ordenador. |
| Servidor y EPUB ahora | Se harán con la fase 1 de contenido rico. |
| Copiar código, resaltado de sintaxis, código en línea en monoespaciada, capítulos por títulos | YAGNI. |
| Validar los huecos sin pintarlos | Se inventarían fórmulas en huecos vacíos. |

## Evidencia medida

Las mediciones se hicieron con el pdf.js del backend, usando `.claude/tools/pdf_spike.mjs`.

**"Cálculo integral (1)"** (`73846bcd-….pdf`, 209 páginas, 17,7 MB)

- **Cuerpo:** Minion-Regular, el 80 % de los caracteres, tamaño h11.
- **Títulos:**
  - AlbertusMedium-Regular: "4.6 Aplicaciones a la Física".
  - AlbertusMT-Italic: "4.6.1 Trabajo" y "Ejercicio 1", en el mismo tamaño que el cuerpo pero de otra familia.
- **Cabecera y pie:**
  - la cabecera es "APLICACIONES DE LA INTEGRAL DEFINIDA" en AlbertusMT-Light-SC700, h7;
  - el número de página va en AlbertusMT, h9.
- **Fuentes matemáticas:** solo un ~1,5 % del texto (Cambria, Symbol, TimesNewRomanPS-ItalicMT).
- **Imágenes:** 82 páginas las llevan, sobre todo entre la 92 y la 154.
- **Página 136:** no tiene imágenes, y las ecuaciones son **huecos verticales sin texto**, es decir, dibujos vectoriales. Los huecos están en y 396→356, 289→230 y 217→157, con un interlineado de 13. La app se las salta sin avisar.
- **Otros defectos visibles hoy:**
  - "fuerza.Ejercicio 1Para", con las palabras pegadas;
  - "x2", con el exponente aplanado;
  - "pro-blema" y "deno-minador", con el guion de corte sin unir;
  - los teléfonos de la página de créditos ("(+593 7) 2050000") salen enmarcados como fórmula.

**"Ciencia de datos desde cero"** (`191f91fe-….pdf`, 300 páginas)

- **Fuentes:**

  | Fuente | Uso | Proporción | Tamaño |
  | --- | --- | --- | --- |
  | LiberationSerif | cuerpo | 64 % | h15 |
  | LiberationMono | **código** | 30 % | h10, bloque en x=74 |
  | LiberationSans | — | 3,3 % | — |
  | SerifaStd-Bold | títulos | — | h20 |
  | LiberationSerif-Bold | pies de figura ("Figura 1.2.") | — | — |

- **Imágenes:** 67 páginas, que son figuras.
- **Página 29:**
  - `def foaf_ids_bad(user):` va en Mono;
  - "( id 4)" también va en Mono, pero metido en una línea Serif, así que es código en línea y debe quedarse en la frase;
  - la primera línea de cada párrafo entra en x=91, frente a x=72 del resto.

**Syncfusion 28.2.12**

- `PdfTextExtractor.extractTextLines({startPageIndex, endPageIndex})` devuelve `List<TextLine>` (`pdf_text_extractor.dart:130`).
- Cada `TextLine` trae `text`, `fontName`, `fontStyle`, `fontSize`, `bounds` (Rect), `pageIndex` y `wordCollection`.
- `TextWord` debería traer la fuente de cada palabra: **comprobarlo al implementar**.
- Syncfusion mutila los pares UTF-16 fuera del plano básico: la 𝑥 (U+1D465, `D835 DC65`) llega como `D835 0C65`. Hay que aplicar `LocalReaderRepository.repairSurrogates` **a cada línea** (lo pidió la sesión "Windows logs monitoring", que lo arregló en `69e4521`).

## Diseño por secciones (aprobado)

### 1. Modelo de bloques y caché

- **Bloques del capítulo.** `Chapter` gana `blocks: List<ChapterBlock>` y conserva `text` y `words`. Tipos de bloque:
  - `paragraph`;
  - `heading`, para ejercicios y secciones;
  - `code`, que conserva `\n` y la sangría;
  - `figure`, con `page` y `rect` en coordenadas del PDF, y la variante fórmula o figura.
- **Las palabras siguen siendo la única referencia** de progreso, resaltado y voz.
  - Cada figura aporta **una palabra marcadora**, "Fórmula" o "Figura". Mientras la voz la dice, se resalta el bloque y los índices no se descuadran.
  - El código **siempre** cuenta sus palabras, aunque la voz lo salte. Así, cambiar el ajuste a mitad de libro no mueve la posición. Es lo mismo que hace hoy `muteFormulaSegments`: conserva las palabras y solo cambia lo que se dice.
- **La pantalla pinta desde `blocks`**, no partiendo el texto por líneas en blanco, porque el código Python tiene líneas en blanco dentro.
- **Caché v6.** La v5 ya la tomó `repairSurrogates`. La primera apertura de cada libro lo vuelve a procesar una vez, y las cachés viejas se borran con `deleteChapterCaches` (`core/storage/chapter_cache_files.dart`).
- **Sin bloques** (capítulos del servidor, cachés antiguas, TXT si no se generan): el comportamiento actual, intacto.
- **"Ver en el libro"** usa la `page` y el `rect` guardados, en lugar de buscar el texto con `PdfPageLocator`, que queda como plan de respaldo.

### 2. Análisis de maquetación del PDF (en el isolate de `_parsePdfFile`)

1. **Extracción.** Cada página se lee con `extractTextLines` y se aplica `repairSurrogates` a cada línea.
2. **Perfil del libro:**
   - la **fuente de cuerpo** es la combinación de fuente y tamaño con más caracteres;
   - de ella salen el interlineado normal (la mediana de la separación entre líneas de cuerpo) y la columna (los márgenes izquierdo y derecho típicos).
3. **Clasificación de cada línea:**
   - **Cabecera o pie de página:** está en la franja superior o inferior, por encima de la primera línea de cuerpo o por debajo de la última, y su fuente y su texto sin dígitos se repiten en ≥ 3 páginas. También un número de página suelto. Se **descarta**.
   - **Código:** la mayoría de las palabras de la línea usan una fuente monoespaciada (`/mono|courier|consol|menlo|inconsolata|code|typewriter|fixed/i`).
     - Se conserva el salto de línea.
     - La sangría se calcula como `(x − x_del_bloque) / ancho_de_carácter`.
     - El código metido en una línea de prosa sigue siendo prosa.
   - **Título:** otra familia de fuente que el cuerpo (familia = nombre sin `-Regular`, `-Italic`, `-Bold`…) o más tamaño (≥ ×1,15). Además, línea corta (menos que la columna) y separada por un hueco encima. No puede ser monoespaciada. Así salen "Ejercicio 1" y "4.6.1 Trabajo".
   - **Cuerpo:** se une en párrafos.
     - Empieza un párrafo nuevo con la sangría de primera línea, con un hueco mayor de ~1,5 interlineados o tras otro bloque.
     - El guion de final de línea seguido de minúscula reconstruye la palabra ("pro-" + "blema").
4. **Ecuaciones y figuras.**
   - Un hueco vertical mayor de ~2 interlineados entre dos líneas conservadas de la misma página, dentro de la columna, es candidato.
   - **Validación de tinta:** cada candidato se pinta en miniatura con pdfrx y solo se queda si tiene tinta. Se hace una vez por libro, durante el aviso de "procesando".
   - Si mide hasta ~4 interlineados es "Fórmula"; si es más alto, "Figura".
5. **Plan B por libro.** Si la fuente de cuerpo tiene menos del 40 % de los caracteres (escaneados, maquetaciones raras), ese libro sigue con el proceso actual: `extractText` + `stripPdfNoise` + reflujo.
6. **Corte en capítulos:** sigue siendo por ~3000 palabras (`_targetWordsPerChapter`), pero sobre bloques y sin partir nunca un bloque de código ni una figura. Detectar capítulos por los títulos queda fuera (YAGNI).

### 3. Cómo se ve en pantalla

- **Título:** algo más grande que el cuerpo, en seminegrita, sin sangría y con aire encima. Se resalta como un párrafo cuando la voz lo lee.
- **Código:**
  - **Formato:** monoespaciada con `fontFamily: 'monospace'` explícita (ver la trampa de `copyWith` en el ADR §7), algo más pequeña que el cuerpo, en un panel con filete lateral y alineado a la izquierda.
  - **Líneas largas:** **no se parten**; el bloque se desplaza en horizontal para conservar la sangría.
  - **Resaltado:** mientras la voz pasa por él, se resalta el bloque entero, no palabra por palabra.
- **Figura:**
  - **Contenido:** el recorte del PDF pintado con pdfrx al ancho de la columna y a la resolución de la pantalla. Se genera solo cuando el bloque va a verse y se guarda en memoria (LRU).
  - **Mientras carga:** el hueco ya tiene la proporción del `rect`, para que el texto no salte.
  - **Al tocarlo:** abre "Ver en el libro" (`formula_source_sheet.dart`) directo en su página.
  - **En los temas oscuro y sepia:** se **invierten solo las fórmulas**. Las figuras grandes se muestran tal cual, con esquinas redondeadas.
- **Párrafos:** como ahora. En los capítulos con bloques **ya no** se aplica `looksLikeFormula`, y con eso se acaban los teléfonos enmarcados.

### 4. Qué dice la voz

- **Plan por bloques.** La voz recibe un plan por bloques. Es la generalización de `splitIsolatingFormulas` (`tts_segmentation.dart:366`): cada bloque especial en su propio segmento y la prosa troceada como hoy. Cada fragmento extra cuesta de 50 a 100 ms en Android.
- **Título:** se lee con una pausa detrás. Si no acaba en punto, se le añade.
- **Código:** según `ReadingPreferences` (campo nuevo, por ejemplo `readCodeAloud`):
  - **Desactivado** (por defecto): dice "Bloque de código." y el seguidor salta sus palabras.
  - **Activado:** se lee como prosa.
  - **Cambiar el ajuste:** vale desde el siguiente play, o al momento si está sonando (`ReaderTtsRestart` en la palabra actual).
  - El ajuste vive en el panel "Ajustes de lectura" (`reading_customization_sheet.dart`): "Leer los bloques de código en voz alta".
- **Figura:** dice su palabra marcadora ("Fórmula." o "Figura.") mientras resalta el bloque. Se apoya en la marca `isFormula` de `SpeakSegment`, o en su generalización.
- **Capítulos sin bloques:** exactamente como hoy, con `looksLikeFormula` y `muteFormulaSegments`.

### 5. Markdown, TXT y verificación

- **Markdown** (`_parseMarkdown`):
  - las vallas ``` y ~~~ pasan a bloque de código literal, descartando la etiqueta de lenguaje;
  - los `###` dentro de un capítulo pasan a títulos sin las almohadillas.
- **TXT:** como hoy. `looksLikeFormula` queda solo para TXT y capítulos del servidor, y gana una regla que excluye teléfonos y faxes (patrones tipo "(+593 7) 2050000", "Fax:", "Tel.", "P.B.X.").
- **EPUB offline:** no soportado (fuera de alcance).

## Pasos de implementación (orden propuesto)

1. **Modelo.**
   - `ChapterBlock` en `features/reader/domain/entities/`.
   - `Chapter.blocks` opcional (vacío = modo actual).
   - Serialización en `_chapterToJson` y `_chapterFromJson` (`local_reader_repository.dart:554` y `:562`).
   - Caché v6 en `_chaptersCachePathFor`.
2. **Clasificador puro** en `features/reader/data/parsing/pdf_layout.dart`. Recibe líneas propias (texto, fuente, tamaño, rect, página y la fuente de cada palabra si existe) y devuelve bloques más candidatos de figura. **No depende de Syncfusion**, para poder probarlo con líneas sintéticas.
3. **Adaptador de Syncfusion** dentro de `_parsePdfFile`:
   - convierte `TextLine` en líneas propias y aplica `repairSurrogates` a cada una;
   - aplica el plan B si no hay fuente de cuerpo;
   - devuelve capítulos con bloques.
4. **Validación de tinta** detrás de la interfaz `InkProbe`, con implementación en pdfrx.
   - PDFium no es seguro entre hilos, así que lo más probable es hacerla en el hilo principal, por lotes, después del parseo. Comprobar si pdfrx ya delega en su propio worker.
   - En los tests, un doble.
5. **Corte en capítulos** por palabras sobre bloques.
6. **Pantalla:**
   - `reader_page.dart` pinta desde `blocks` (hoy usa `chapter.paragraphs`, en `:1602`, y `_cachedParagraphs`);
   - widgets de título, código y figura, reutilizando la idea de `_FormulaFrame` (`:2479`);
   - "Ver en el libro" con `page` y `rect`.
7. **Voz:**
   - generalizar `splitIsolatingFormulas` y `muteFormulaSegments` (`tts_segmentation.dart`) a bloques, y llevar los bloques hasta `DeviceTtsRepository.speak` (`:499`), con su firma en `tts_repository.dart:14` y el proxy;
   - añadir el ajuste en `ReadingPreferences` y en el panel.
8. **Markdown y TXT:** las vallas y los títulos en `_parseMarkdown`, y la regla de teléfonos en `looksLikeFormula`.
9. **Verificación:** en el Pixel con los dos libros, ver la lista de abajo, y una prueba de humo en Windows.
10. **Documentación:** actualizar el ADR 13 (estado y desviaciones forzadas, si las hay) y persistir los aprendizajes en el agente con saldo cero (límite de 1000 palabras).

## Tests

- **Clasificador**, con líneas sintéticas:
  - fuente de cuerpo;
  - cabeceras y pies descartados;
  - código con su sangría reconstruida;
  - código en línea que sigue en la prosa;
  - títulos por otra familia o por tamaño;
  - párrafos por sangría y por huecos;
  - guion de corte;
  - huecos candidatos, y el plan B sin fuente dominante.
- **Integración con un PDF generado con Syncfusion:**
  - cuerpo en Times y código en Courier;
  - una forma dibujada en un hueco y otro hueco vacío;
  - el flujo completo de `LocalReaderRepository`, con `InkProbe` doble.
- **Caché:** v6 escrita, v5 borrada, y la ida y vuelta de los bloques en JSON.
- **Voz por bloques:**
  - título con pausa;
  - código en los dos modos del ajuste;
  - figura con su marcadora;
  - índices de palabras conservados.
- **Widgets:** código (monoespaciada, desplazamiento horizontal) y figura (proporción mientras carga).
- **Markdown:** vallas y `###`.
- **`looksLikeFormula`:** deja de tomar teléfonos por fórmulas.

## Verificación en dispositivo (criterio de hecho)

Se hace en el Pixel 10 Pro XL. Ver en `memory/entorno_herramientas.md` cómo instalar la build de debug sin perder datos. Allí está también la advertencia de **no usar `uiautomator dump`**: abre el asistente de "Accesibilidad con interruptores" del usuario.

- **Cálculo, página 136:**
  - las tres ecuaciones aparecen recortadas en su sitio;
  - "4.6.1 Trabajo" y "Ejercicio 1" salen como títulos;
  - no hay cabeceras de página;
  - los teléfonos de los créditos salen como texto normal;
  - desaparecen "pro-blema" y las palabras pegadas.
- **Python, página 29:**
  - `def foaf_ids_bad(user):` sale como bloque con su sangría;
  - "( id 4)" sigue dentro de la frase;
  - la figura 1.2 sale recortada.
- **Voz:** "Fórmula." en las ecuaciones y "Bloque de código." en el código, con el ajuste probado en los dos sentidos.
- **Tema oscuro:** las fórmulas salen invertidas y las figuras tal cual.
- **Primera apertura de cada libro:** medir su duración (el de cálculo pesa 17,7 MB), sin congelar la pantalla.
- **Windows:** abrir los dos libros sin errores. Es el entorno de la sesión "Windows logs monitoring".
- **Cierre:** `flutter analyze` limpio, la suite en verde y commits temáticos sin firma de IA.

## Riesgos y mitigaciones

- **Dos columnas, escaneados u OCR con muchas fuentes:** plan B por libro.
- **Rendimiento:**
  - medir `extractTextLines` frente a `extractText`;
  - pintar la tinta por lotes y a baja resolución (~0,5 px/pt).
- **Títulos en la misma familia que el cuerpo y en negrita:** usar `fontStyle` bold, junto con línea corta y aislada.
- **La palabra marcadora cambia los recuentos de palabras:** la v6 lo reprocesa todo, así que el progreso guardado puede desplazarse una vez. Aceptado.
- **Figuras cerca del borde de la página:** de momento solo cuentan los huecos entre líneas de la misma página.

## Coordinación

- **Otra sesión de Claude**, "Windows logs monitoring", trabaja en el mismo repo (Windows). Comprobarlo con ListAgents antes de tocar `local_reader_repository.dart`, y commitear solo los archivos propios (`git add` por ruta).
- **`repairSurrogates`** ya está en `69e4521`.

## Pendientes ajenos a este plan

Siguen en la memoria del proyecto (`project_state.md`):

- el push de 33 commits;
- verificar el modo concentración, para lo que el usuario debe conceder "Acceso a No molestar";
- el login offline sin sesión persistente;
- el tamaño del APK;
- `dart:io` en los repositorios offline;
- las auditorías del modo conectado.
