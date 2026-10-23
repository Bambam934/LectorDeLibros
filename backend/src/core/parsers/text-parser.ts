import type { BookParser, ParsedBook, ParsedChapter } from './types.js';
import { countWords, MAX_WORDS_PER_CHAPTER } from './types.js';

const HEADING_RE = /^(?:#{1,6}\s+.+|(?:Capítulo|Chapter|CAPÍTULO|CHAPTER)\s+\S+.*|(?:PARTE|PART)\s+[IVXLCDM\d]+.*)$/im;
const SEPARATOR_RE = /^\s*(?:\*{3,}|-{3,}|_{3,})\s*$/;

const CHAPTER_HEADING_RE = /^(?:#{1,6}\s+(.+)|((?:Capítulo|Chapter|CAPÍTULO|CHAPTER)\s+\S+.*|(?:PARTE|PART)\s+[IVXLCDM\d]+.*))$/im;

export class TextParser implements BookParser {
  readonly fileFormat: 'txt' | 'md';

  constructor(format: 'txt' | 'md') {
    this.fileFormat = format;
  }

  async parse(buffer: Buffer): Promise<ParsedBook> {
    const raw = this.decode(buffer);
    const isMarkdown = this.fileFormat === 'md';
    const cleaned = isMarkdown ? stripMarkdownSyntax(raw) : raw;

    const chapters = this.splitIntoChapters(cleaned);
    if (chapters.length === 0) {
      throw new Error('El archivo no contiene texto legible.');
    }

    const totalWords = chapters.reduce((sum, c) => sum + c.wordCount, 0);
    const title = this.extractTitle(cleaned) ?? 'Documento sin título';

    return {
      title,
      author: null,
      language: 'es',
      fileFormat: this.fileFormat,
      chapters,
      totalWords
    };
  }

  // Igual que `decodeTextBytes` del cliente (text_decoding.dart): UTF-8 sin
  // el BOM y, si los bytes no lo son, Windows-1252, el "ANSI" del Bloc de
  // notas. Con Latin-1 se perdían €, comillas, rayas y puntos suspensivos.
  private decode(buffer: Buffer): string {
    const hasBom = buffer.length >= 3 &&
      buffer[0] === 0xef && buffer[1] === 0xbb && buffer[2] === 0xbf;
    const body = hasBom ? buffer.subarray(3) : buffer;
    if (isValidUtf8(body)) return body.toString('utf-8');
    return decodeWindows1252(body);
  }

  private extractTitle(text: string): string | null {
    const firstLine = text.split('\n').find((l) => l.trim().length > 0);
    if (!firstLine) return null;
    const headingMatch = firstLine.match(/^#{1,6}\s+(.+)$/);
    if (headingMatch?.[1]) return headingMatch[1].trim();
    return firstLine.trim().slice(0, 200) || null;
  }

  private splitIntoChapters(text: string): ParsedChapter[] {
    const lines = text.split('\n');
    const segments: Array<{ title: string; lines: string[] }> = [];
    let currentTitle = 'Capítulo 1';
    let currentLines: string[] = [];

    for (const line of lines) {
      const headingMatch = line.match(CHAPTER_HEADING_RE);
      const isSeparator = SEPARATOR_RE.test(line);

      if (headingMatch || isSeparator) {
        if (currentLines.length > 0) {
          segments.push({ title: currentTitle, lines: currentLines });
          currentLines = [];
        }

        if (headingMatch) {
          currentTitle = headingMatch[1]?.trim() ?? headingMatch[2]?.trim() ?? currentTitle;
        } else {
          currentTitle = `Capítulo ${segments.length + 2}`;
        }
      } else {
        currentLines.push(line);
      }
    }

    if (currentLines.length > 0) {
      segments.push({ title: currentTitle, lines: currentLines });
    }

    if (segments.length <= 1) {
      return this.splitByWordCount(text);
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
}

function isValidUtf8(buffer: Buffer): boolean {
  const utf8Decoded = buffer.toString('utf-8');
  const reEncoded = Buffer.from(utf8Decoded, 'utf-8');
  if (reEncoded.length !== buffer.length) return false;
  return reEncoded.equals(buffer);
}

// 0x80-0x9F de Windows-1252; el resto de bytes coincide con Latin-1. Los
// cinco huecos sin asignar (0x81, 0x8D, 0x8F, 0x90, 0x9D) quedan como en
// Latin-1. Tabla propia: el `TextDecoder('windows-1252')` de Node decodifica
// como Latin-1 (0x80 sale U+0080, no €).
const CP1252_HIGH = [
  0x20ac, 0x0081, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021, // 80-87
  0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008d, 0x017d, 0x008f, // 88-8F
  0x0090, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014, // 90-97
  0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0x009d, 0x017e, 0x0178 // 98-9F
];

function decodeWindows1252(buffer: Buffer): string {
  let out = '';
  for (let start = 0; start < buffer.length; start += 8192) {
    const end = Math.min(start + 8192, buffer.length);
    const units = new Array<number>(end - start);
    for (let i = start; i < end; i++) {
      const b = buffer[i]!;
      units[i - start] = b >= 0x80 && b < 0xa0 ? CP1252_HIGH[b - 0x80]! : b;
    }
    out += String.fromCharCode(...units);
  }
  return out;
}

// Enlaces e imágenes en tiempo LINEAL. Los patrones anteriores
// (`\[([^\]]+)\]\([^)]+\)`) eran cuadráticos con muchos `[` sin `]`: la clase
// recorría hasta el final desde cada uno (medido: ×4 al duplicar). Excluir el
// propio `[` corta cada intento en el siguiente. La URL admite un nivel de
// paréntesis anidados, como en "https://es.wikipedia.org/wiki/C_(lenguaje)",
// que antes dejaba un ")" suelto en el texto leído.
const MD_IMAGE_RE = /!\[([^[\]]*)\]\((?:[^()]|\([^()]*\))*\)/g;
const MD_LINK_RE = /\[([^[\]]+)\]\((?:[^()]|\([^()]*\))*\)/g;

function stripMarkdownSyntax(text: string): string {
  return text
    // Imágenes ANTES que enlaces: si no, el patrón de enlaces se comía
    // "[alt](url)" de "![alt](url)" y en el texto quedaba "!alt".
    .replace(MD_IMAGE_RE, '')
    .replace(MD_LINK_RE, '$1')
    .replace(/^#{1,6}\s+/gm, '')
    .replace(/(\*{1,3}|_{1,3})(.+?)\1/g, '$2')
    .replace(/~~(.+?)~~/g, '$1')
    .replace(/`{1,3}[^`]*`{1,3}/g, '')
    .replace(/^>\s?/gm, '')
    .replace(/^[-*+]\s+/gm, '')
    .replace(/^\d+\.\s+/gm, '')
    .replace(/^---+$|^\*\*\*+$|^___+$/gm, '')
    .trim();
}
