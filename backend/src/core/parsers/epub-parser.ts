import AdmZip from 'adm-zip';
import { parseStringPromise } from 'xml2js';
import path from 'node:path';

import type { BookParser, ParsedBook } from './types.js';
import { countWords } from './types.js';

const CONTAINER_PATH = 'META-INF/container.xml';

export class EpubParser implements BookParser {
  async parse(buffer: Buffer): Promise<ParsedBook> {
    const zip = new AdmZip(buffer);

    const containerEntry = zip.getEntry(CONTAINER_PATH);
    if (!containerEntry) {
      throw new Error('EPUB inválido: falta META-INF/container.xml');
    }
	const containerXml = await parseStringPromise(containerEntry.getData().toString('utf-8'), {
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
	const opfXml = await parseStringPromise(opfEntry.getData().toString('utf-8'), {
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

      const html = chapterEntry.getData().toString('utf-8');
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

function htmlToPlainText(html: string): string {
  return html
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
    .replace(/<\/(p|div|h[1-6]|li|br)>/gi, '\n')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
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

function extractTitleFromHtml(html: string): string | null {
  const h1 = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  if (h1?.[1]) return htmlToPlainText(h1[1]).trim() || null;
  const h2 = html.match(/<h2[^>]*>([\s\S]*?)<\/h2>/i);
  if (h2?.[1]) return htmlToPlainText(h2[1]).trim() || null;
  const titleTag = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (titleTag?.[1]) return titleTag[1].trim() || null;
  return null;
}
