import AdmZip from 'adm-zip';
import { parseStringPromise } from 'xml2js';
import path from 'node:path';
import { inflateRawSync } from 'node:zlib';

import type { BookParser, ParsedBook } from './types.js';
import { countWords } from './types.js';

const CONTAINER_PATH = 'META-INF/container.xml';

/**
 * Quita el DOCTYPE (contra bombas XML, V-11) en tiempo LINEAL.
 *
 * El patrón anterior, `<!DOCTYPE[^>]*(\[[\s\S]*?\])?>`, era cuadrático: con
 * muchos "<!DOCTYPE" sin cerrar, `[^>]*` recorría hasta el final desde cada
 * uno (medido: 1,6 s con 16.000 repeticiones, ×4 al duplicar). Aquí cada
 * clase se detiene en el siguiente `<`, `>` o `[`, así que ningún intento
 * cruza el siguiente DOCTYPE. Un subconjunto interno que contenga `[` no se
 * reconoce y el XML estricto lo rechaza después: falla cerrado.
 */
const DOCTYPE_RE = /<!DOCTYPE[^<>[]*(\[[^[\]]*\])?\s*>/gi;

/**
 * Topes de bytes DESCOMPRIMIDOS, por entrada y para el libro entero.
 *
 * Un EPUB es un ZIP subido por el usuario. `entry.getData()` reserva memoria
 * según el tamaño que DECLARA el propio ZIP (adm-zip ≤0.6.0, CVE-2026-39244):
 * un archivo de ~120 bytes puede pedir 4 GB, y un capítulo de pocos KB puede
 * inflarse a gigas. Por eso no se usa `getData()`: se toman los datos
 * comprimidos tal cual y se inflan con `maxOutputLength`, un tope que no
 * depende de lo que diga el ZIP.
 *
 * Un capítulo XHTML real no se acerca a 16 MiB, y el límite de 5M palabras
 * del importador ronda los 30 MiB de texto.
 */
const MAX_ENTRY_BYTES = 16 * 1024 * 1024;
const MAX_TOTAL_BYTES = 128 * 1024 * 1024;

/** Lee una entrada del ZIP sin dejar que su tamaño declarado decida nada. */
function readEntryText(entry: AdmZip.IZipEntry, budget: { remaining: number }): string {
  const limit = Math.min(MAX_ENTRY_BYTES, budget.remaining);
  const compressed = entry.getCompressedData();
  let data: Buffer;
  switch (entry.header.method) {
    case 0: // STORED: sin comprimir
      if (compressed.length > limit) throw tooLarge(entry.entryName);
      data = compressed;
      break;
    case 8: // DEFLATED
      try {
        data = inflateRawSync(compressed, { maxOutputLength: limit });
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code === 'ERR_BUFFER_TOO_LARGE') {
          throw tooLarge(entry.entryName);
        }
        throw new Error(`EPUB inválido: no se pudo descomprimir ${entry.entryName}`);
      }
      break;
    default:
      throw new Error(`EPUB inválido: compresión no soportada en ${entry.entryName}`);
  }
  budget.remaining -= data.length;
  return data.toString('utf-8');
}

function tooLarge(name: string): Error {
  return new Error(`EPUB demasiado grande al descomprimir (${name})`);
}

export class EpubParser implements BookParser {
  async parse(buffer: Buffer): Promise<ParsedBook> {
    const zip = new AdmZip(buffer);
    const budget = { remaining: MAX_TOTAL_BYTES };

    const containerEntry = zip.getEntry(CONTAINER_PATH);
    if (!containerEntry) {
      throw new Error('EPUB inválido: falta META-INF/container.xml');
    }
	const containerXml = await parseStringPromise(
		readEntryText(containerEntry, budget).replace(DOCTYPE_RE, ''), {
		explicitCharkey: true,
		normalizeTags: true,
		attrkey: '$',
		charkey: '_',
		emptyTag: undefined,
		mergeAttrs: false,
		strict: true
	});
    const opfPath: string | undefined = containerXml?.container?.rootfiles?.[0]?.rootfile?.[0]?.$?.['full-path'];
    if (!opfPath) {
      throw new Error('EPUB inválido: container.xml no apunta a un .opf');
    }

    const opfEntry = zip.getEntry(opfPath);
    if (!opfEntry) {
      throw new Error(`EPUB inválido: no se encontró ${opfPath}`);
    }
	const opfXml = await parseStringPromise(
		readEntryText(opfEntry, budget).replace(DOCTYPE_RE, ''), {
		explicitCharkey: true,
		normalizeTags: true,
		attrkey: '$',
		charkey: '_',
		emptyTag: undefined,
		mergeAttrs: false,
		strict: true
	});
    const pkg = opfXml.package ?? opfXml['opf:package'];
    if (!pkg) {
      throw new Error('EPUB inválido: estructura .opf no reconocida');
    }

    const metadata = pkg.metadata?.[0] ?? {};
    const title = pickText(metadata['dc:title'] ?? metadata.title) ?? 'Libro sin título';
    const author = pickText(metadata['dc:creator'] ?? metadata.creator);
    const language = pickText(metadata['dc:language'] ?? metadata.language) ?? 'es';

    const manifestItems: Array<{ id: string; href: string; mediaType: string }> = (
      pkg.manifest?.[0]?.item ?? []
    ).map((it: { $: { id: string; href: string; ['media-type']: string } }) => ({
      id: it.$.id,
      href: it.$.href,
      mediaType: it.$['media-type']
    }));
    const manifestById = new Map(manifestItems.map((it) => [it.id, it]));

    const spineRefs: string[] = (pkg.spine?.[0]?.itemref ?? []).map(
      (ref: { $: { idref: string } }) => ref.$.idref
    );

    const opfDir = path.posix.dirname(opfPath.replace(/\\/g, '/'));
    const chapters: Array<{ title: string; orderIndex: number; text: string; wordCount: number }> = [];
    let order = 1;

    for (const idref of spineRefs) {
      const item = manifestById.get(idref);
      if (!item) continue;
      if (!/x?html/i.test(item.mediaType)) continue;

		const chapterPath = opfDir ? `${opfDir}/${item.href}` : item.href;
		const normalizedChapterPath = chapterPath.replace(/\\/g, '/').replace(/\/\.\.\//g, '/').replace(/\/\.\//g, '/');
		if (normalizedChapterPath.includes('..')) {
			continue;
		}
		const chapterEntry = zip.getEntry(normalizedChapterPath);
      if (!chapterEntry) continue;

      const html = readEntryText(chapterEntry, budget);
      const text = htmlToPlainText(html);
      if (!text.trim()) continue;

      const chapterTitle = extractTitleFromHtml(html) ?? `Capítulo ${order}`;
      const wordCount = countWords(text);

      chapters.push({ title: chapterTitle, orderIndex: order, text, wordCount });
      order += 1;
    }

    const totalWords = chapters.reduce((sum, c) => sum + c.wordCount, 0);

    return {
      title,
      author: author ?? null,
      language,
      fileFormat: 'epub',
      chapters,
      totalWords
    };
  }
}

function pickText(node: unknown): string | null {
  if (!node) return null;
  if (typeof node === 'string') return node;
  if (Array.isArray(node) && node.length > 0) {
    const first = node[0];
    if (typeof first === 'string') return first;
    if (typeof first === 'object' && first !== null && '_' in first) {
      return String((first as { _: string })._);
    }
  }
  return null;
}

/**
 * Localiza un bloque `<tag ...>...</tag>` a partir de `from`, sin retroceder.
 *
 * Usa regex `/gi` con `lastIndex` y no `toLowerCase()` + `indexOf`: pasar a
 * minúsculas puede cambiar la longitud del texto (la "İ" turca se convierte
 * en dos unidades) y los índices dejarían de valer para el original.
 */
function findBlock(
  html: string,
  tag: string,
  from: number,
): { start: number; contentStart: number; contentEnd: number; end: number } | null {
  const openRe = new RegExp(`<${tag}`, 'gi');
  openRe.lastIndex = from;
  const open = openRe.exec(html);
  if (!open) return null;
  const tagEnd = html.indexOf('>', open.index + open[0].length);
  if (tagEnd < 0) return null;
  const closeRe = new RegExp(`</${tag}>`, 'gi');
  closeRe.lastIndex = tagEnd + 1;
  const close = closeRe.exec(html);
  if (!close) return null;
  return {
    start: open.index,
    contentStart: tagEnd + 1,
    contentEnd: close.index,
    end: close.index + close[0].length,
  };
}

/**
 * Quita los bloques `<tag ...>...</tag>` en tiempo lineal.
 *
 * Sustituye a `/<script[^>]*>[\s\S]*?<\/script>/gi`, que era cuadrático: con
 * muchos `<script>` sin cerrar, el `*?` recorría hasta el final desde cada uno
 * (medido: ×4 al duplicar la entrada). Conserva su comportamiento: si un
 * bloque no tiene cierre, se deja tal cual y la limpieza de etiquetas de
 * después quita la etiqueta suelta.
 */
function stripBlocks(html: string, tag: string): string {
  let out = '';
  let pos = 0;
  for (let block = findBlock(html, tag, 0); block; block = findBlock(html, tag, pos)) {
    out += html.slice(pos, block.start);
    pos = block.end;
  }
  return out + html.slice(pos);
}

function htmlToPlainText(html: string): string {
  return stripBlocks(stripBlocks(html, 'script'), 'style')
    .replace(/<\/(p|div|h[1-6]|li|br)>/gi, '\n')
    .replace(/<br\s*\/?>/gi, '\n')
    // `[^<>]` y no `[^>]`: con muchos `<` sin `>`, la clase anterior
    // recorría hasta el final desde cada uno (cuadrático). Así cada intento
    // se detiene en el siguiente `<`.
    .replace(/<[^<>]+>/g, '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

/**
 * Título del capítulo: el primer `<h1>`, si no el primer `<h2>`, si no el
 * `<title>`.
 *
 * Con `findBlock` y no con `html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i)`: ese
 * `match` probaba CADA `<h1` del documento y, con miles sin cerrar, recorría
 * hasta el final desde cada uno (cuadrático, medido).
 */
function extractTitleFromHtml(html: string): string | null {
  for (const tag of ['h1', 'h2']) {
    const block = findBlock(html, tag, 0);
    const inner = block ? html.slice(block.contentStart, block.contentEnd) : '';
    if (inner) return htmlToPlainText(inner).trim() || null;
  }
  const title = findBlock(html, 'title', 0);
  const inner = title ? html.slice(title.contentStart, title.contentEnd).trim() : '';
  return inner || null;
}
