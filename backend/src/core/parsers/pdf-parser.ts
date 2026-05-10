import type { BookParser, ParsedBook, ParsedChapter } from './types.js';
import { countWords } from './types.js';

const MAX_WORDS_PER_CHAPTER = 5000;
const HEADING_RE = /^(?:(?:Capítulo|Chapter|CAPÍTULO|CHAPTER)\s+\S+.*|(?:PARTE|PART)\s+[IVXLCDM\d]+.*)$/im;

export class PdfParser implements BookParser {
  async parse(buffer: Buffer, filename?: string): Promise<ParsedBook> {
    const pdfjsLib = await importPdfjs();

    const doc = await pdfjsLib.getDocument({ data: new Uint8Array(buffer) }).promise;
    const numPages = doc.numPages;

    if (numPages === 0) {
      throw new Error('El PDF no contiene páginas.');
    }

    const outline = await this.extractOutline(doc);
    const pageTexts = await this.extractPageTexts(doc);

    const totalText = pageTexts.join('\n');
    if (!totalText.trim()) {
      throw new Error('El PDF no contiene texto extraíble. Puede ser un PDF de solo imágenes.');
    }

    const chapters = outline.length > 0
      ? this.splitByOutline(pageTexts, outline, numPages)
      : this.splitHeuristically(pageTexts);

    if (chapters.length === 0) {
      throw new Error('No se pudieron extraer capítulos del PDF.');
    }

    const title = (await this.extractTitle(doc, pageTexts)) ?? this.titleFromFilename(filename) ?? 'PDF sin título';
    const author = await this.extractAuthor(doc);
    const language = 'es';
    const totalWords = chapters.reduce((sum, c) => sum + c.wordCount, 0);

    return { title, author, language, fileFormat: 'pdf', filename, chapters, totalWords };
  }

  private async extractOutline(doc: PDFDocument): Promise<Array<{ title: string; pageNumber: number }>> {
    try {
      const pdfOutline = await doc.getOutline();
      if (!pdfOutline || pdfOutline.length === 0) return [];

      const result: Array<{ title: string; pageNumber: number }> = [];
      for (const item of pdfOutline) {
        if (!item.dest) continue;
        let pageNumber: number;
        try {
          const dest = typeof item.dest === 'string'
            ? await doc.getDestination(item.dest)
            : item.dest;
          const pageIdx = await doc.getPageIndex(dest[0]);
          pageNumber = pageIdx + 1;
        } catch {
          continue;
        }
        result.push({ title: item.title, pageNumber });
      }
      return result;
    } catch {
      return [];
    }
  }

  private async extractPageTexts(doc: PDFDocument): Promise<string[]> {
    const texts: string[] = [];
    for (let i = 1; i <= doc.numPages; i++) {
      const page = await doc.getPage(i);
      const content = await page.getTextContent();
      const pageText = content.items
        .map((item: Record<string, unknown>) => String(item.str ?? ''))
        .join(' ');
      texts.push(pageText);
    }
    return texts;
  }

  private splitByOutline(
    pageTexts: string[],
    outline: Array<{ title: string; pageNumber: number }>,
    numPages: number
  ): ParsedChapter[] {
    const chapters: ParsedChapter[] = [];
    const sortedOutline = [...outline].sort((a, b) => a.pageNumber - b.pageNumber);

    for (let i = 0; i < sortedOutline.length; i++) {
      const startPage = sortedOutline[i]!.pageNumber - 1;
      const endPage = i + 1 < sortedOutline.length
        ? sortedOutline[i + 1]!.pageNumber - 1
        : numPages;

      const chapterText = pageTexts
        .slice(startPage, endPage)
        .join('\n')
        .trim();

      if (!chapterText) continue;

      chapters.push({
        title: sortedOutline[i]!.title,
        orderIndex: chapters.length + 1,
        text: chapterText,
        wordCount: countWords(chapterText)
      });
    }

    if (chapters.length === 0) {
      return this.splitHeuristically(pageTexts);
    }

    return chapters;
  }

  private splitHeuristically(pageTexts: string[]): ParsedChapter[] {
    const fullText = pageTexts.join('\n\n');
    const lines = fullText.split('\n');

    const segments: Array<{ title: string; lines: string[] }> = [];
    let currentTitle = 'Capítulo 1';
    let currentLines: string[] = [];

    for (const line of lines) {
      const trimmed = line.trim();
      const isHeading = HEADING_RE.test(trimmed);
      const isLargeShortLine = trimmed.length > 0
        && trimmed.length < 80
        && !trimmed.endsWith('.')
        && !trimmed.endsWith(',')
        && trimmed === trimmed.toUpperCase()
        && trimmed.length > 3;

      if (isHeading || isLargeShortLine) {
        if (currentLines.length > 0) {
          segments.push({ title: currentTitle, lines: currentLines });
          currentLines = [];
        }
        currentTitle = isHeading ? trimmed : trimmed;
      } else {
        currentLines.push(line);
      }
    }

    if (currentLines.length > 0) {
      segments.push({ title: currentTitle, lines: currentLines });
    }

    if (segments.length <= 1) {
      return this.splitByWordCount(fullText);
    }

    return segments
      .filter((s) => s.lines.join('\n').trim().length > 0)
      .map((s, i) => {
        const chapterText = s.lines.join('\n').trim();
        return {
          title: s.title,
          orderIndex: i + 1,
          text: chapterText,
          wordCount: countWords(chapterText)
        };
      });
  }

  private splitByWordCount(text: string): ParsedChapter[] {
    const words = text.trim().split(/\s+/).filter(Boolean);
    if (words.length === 0) return [];

    const chapterCount = Math.max(1, Math.ceil(words.length / MAX_WORDS_PER_CHAPTER));
    const chapters: ParsedChapter[] = [];

    for (let i = 0; i < chapterCount; i++) {
      const start = i * MAX_WORDS_PER_CHAPTER;
      const end = Math.min(start + MAX_WORDS_PER_CHAPTER, words.length);
      const chapterWords = words.slice(start, end);
      const chapterText = chapterWords.join(' ');

      chapters.push({
        title: chapterCount === 1 ? 'Capítulo 1' : `Capítulo ${i + 1}`,
        orderIndex: i + 1,
        text: chapterText,
        wordCount: chapterWords.length
      });
    }

    return chapters;
  }

  private async extractTitle(doc: PDFDocument, pageTexts: string[]): Promise<string | null> {
    try {
      const metadata = await doc.getMetadata();
      const info = metadata?.info as Record<string, string> | undefined;
      if (info?.Title?.trim()) return info.Title.trim();
    } catch { /* fall through */ }

    // pdfjs une items con espacios → separar por posición vertical aproximada.
    const firstPage = pageTexts[0] ?? '';
    // Intentar separar por múltiples espacios como proxy de salto de línea.
    const lines = firstPage
      .split(/\s{3,}|\n/)
      .map(l => l.trim())
      .filter(Boolean);

    const PAGE_NUM_RE = /^\d+$/;
    const HEADER_FOOTER_RE = /^(?:p[aá]gina|page|hoja|cap[ií]tulo|chapter)\s*\d/i;
    const ROMAN_NUM_RE = /^[ivxlcdm]+\.?$/i;

    for (const line of lines) {
      if (line.length > 100) continue;
      if (PAGE_NUM_RE.test(line)) continue;
      if (HEADER_FOOTER_RE.test(line)) continue;
      if (ROMAN_NUM_RE.test(line)) continue;
      if (line.length < 2) continue;
      return line;
    }

    return null;
  }

  private titleFromFilename(filename: string | undefined): string | null {
    if (!filename) return null;
    const stem = filename.replace(/\.[^.]+$/, '');
    if (!stem) return null;
    const title = stem
      .replace(/[-_]+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .replace(/\b\w/g, c => c.toUpperCase());
    return title || null;
  }

  private async extractAuthor(doc: PDFDocument): Promise<string | null> {
    try {
      const metadata = await doc.getMetadata();
      const info = metadata?.info as Record<string, string> | undefined;
      if (info?.Author?.trim()) return info.Author.trim();
    } catch { /* fall through */ }
    return null;
  }
}

type PDFDocument = {
  numPages: number;
  getPage(pageNum: number): Promise<{
    getTextContent(): Promise<{
      items: Array<Record<string, unknown>>;
    }>;
  }>;
  getOutline(): Promise<Array<{ title: string; dest: string | unknown[] }>> | null;
  getDestination(dest: string): Promise<unknown[]>;
  getPageIndex(dest: unknown): Promise<number>;
  getMetadata(): Promise<{ info?: Record<string, unknown> }>;
};

type PDFJSLib = {
  getDocument(params: { data: Uint8Array }): { promise: Promise<PDFDocument> };
  GlobalWorkerOptions: { workerSrc: string };
};

async function importPdfjs(): Promise<PDFJSLib> {
  try {
    const pdfjsLib = await import('pdfjs-dist/legacy/build/pdf.mjs') as unknown as PDFJSLib;
    return pdfjsLib;
  } catch {
    throw new Error(
      'pdfjs-dist no está instalado. Ejecuta: npm install pdfjs-dist'
    );
  }
}
