/**
 * Limpieza del texto extraído de un PDF.
 *
 * Contraparte de servidor de `LocalReaderRepository.reflowExtractedText()` y
 * `stripPdfNoise()` (lectorsync/lib/features/reader/data/repositories/
 * local_reader_repository.dart), validadas en 2026-07-21 contra un libro de
 * cálculo real. Sin esto, un libro procesado en el servidor conserva el índice,
 * los encabezados repetidos y las palabras partidas por el corte de línea, y el
 * TTS acaba leyendo "FERNANDO ARAUJO RODRÍGUEZ veinte" en cada página.
 *
 * La diferencia con el cliente: pdfjs ya une los fragmentos de una página con
 * espacios (`items.map(...).join(' ')` en pdf-parser.ts), así que aquí NO hay
 * saltos de línea que rehacer — hay espacios de más y guiones colgando. Por eso
 * el reflow es por espacios y no por líneas.
 *
 * NO toca las ecuaciones: un PDF matemático seguirá con el texto de sus
 * fórmulas aplanado (eso requiere renderizar la página, no filtrar texto).
 */

/**
 * Encabezado/pie en mayúsculas con el número de página **pegado**:
 * "INTEGRAL DEFINIDA81".
 *
 * El último carácter del grupo es obligatoriamente una mayúscula, no un
 * espacio. Sin esa exigencia la clase perezosa `[A-ZÁÉÍÓÚÑ ]` se extendía a
 * través del espacio hasta el primer dígito que encontrara, y "CAPÍTULO 1"
 * casaba con el grupo "CAPÍTULO ": tres capítulos abriendo página bastaban
 * para superar MIN_HEADER_REPEATS y `cleanPdfPages` borraba el encabezado
 * REAL de todos ellos — con lo que `splitHeuristically`, que busca líneas
 * que empiecen por "Capítulo", dejaba de detectarlos.
 *
 * Un número separado por espacio ("CAPÍTULO 1", "TEOREMA 4") es numeración
 * del propio libro; pegado ("DEFINIDA81") es el número de página que el
 * extractor unió al encabezado.
 */
const HEADER_RE =
  /^([A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ ]{3,}?[A-ZÁÉÍÓÚÑ])\d{1,4}(?=\s|[A-Za-zÁÉÍÓÚÑáéíóúñ])/;

/** Entrada de tabla de contenidos: "Capítulo 1 .......... 19". */
const INDEX_ENTRY_RE = /[^.]{0,120}?\.{5,}\s*\d{1,4}\s*/g;

/** Palabra partida por el corte de línea: "consu- mismo" → "consumismo". */
const SOFT_HYPHEN_RE = /(\p{Ll})-\s+(\p{Ll})/gu;

/** Número de páginas en las que un encabezado debe repetirse para considerarlo ruido. */
const MIN_HEADER_REPEATS = 3;

/**
 * Reúne una página aplanada por pdfjs: colapsa los espacios sobrantes y vuelve
 * a pegar las palabras que el salto de línea partió con guion.
 *
 * Solo une `minúscula-guion-espacio-minúscula` para no tocar los guiones
 * legítimos ("teórico-práctico" no lleva espacio; "20 - 25" lleva espacio antes).
 */
export function reflowPageText(pageText: string): string {
  return pageText
    .replace(SOFT_HYPHEN_RE, '$1$2')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Quita las entradas de tabla de contenidos de una página.
 *
 * Recorta solo los tramos con relleno de puntos, no la página entera: un índice
 * puede compartir página con el inicio del primer capítulo.
 */
export function stripIndexEntries(pageText: string): string {
  return pageText.replace(INDEX_ENTRY_RE, ' ').replace(/\s+/g, ' ').trim();
}

/**
 * Limpia todas las páginas de un PDF **preservando la cardinalidad del array**:
 * `splitByOutline()` indexa por número de página, así que una página que queda
 * vacía tras la limpieza debe seguir ocupando su posición.
 *
 * Los encabezados solo se recortan si el mismo prefijo aparece en al menos
 * {@link MIN_HEADER_REPEATS} páginas, para no borrar un título legítimo que
 * coincida una única vez.
 */
export function cleanPdfPages(pages: string[]): string[] {
  const reflowed = pages.map((p) => stripIndexEntries(reflowPageText(p)));

  const counts = new Map<string, number>();
  for (const page of reflowed) {
    const match = HEADER_RE.exec(page);
    if (!match) continue;
    const header = match[1]!.trim();
    counts.set(header, (counts.get(header) ?? 0) + 1);
  }

  const repeated = new Set(
    [...counts.entries()]
      .filter(([, n]) => n >= MIN_HEADER_REPEATS)
      .map(([header]) => header)
  );

  if (repeated.size === 0) return reflowed;

  return reflowed.map((page) => {
    const match = HEADER_RE.exec(page);
    if (!match || !repeated.has(match[1]!.trim())) return page;
    return page.slice(match[0].length).trim();
  });
}
