import type { BookParser, ParsedBook, ParsedChapter } from './types.js';
import { countWords } from './types.js';

const HEADING_RE = /^(?:#{1,6}\s+.+|(?:Capítulo|Chapter|CAPÍTULO|CHAPTER)\s+\S+.*|(?:PARTE|PART)\s+[IVXLCDM\d]+.*)$/im;
const SEPARATOR_RE = /^\s*(?:\*{3,}|-{3,}|_{3,})\s*$/;
const MAX_WORDS_PER_CHAPTER = 5000;
const ENCODING_FALLBACK = 'latin1';

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

  private decode(buffer: Buffer): string {
    const utf8 = buffer.toString('utf-8');
    if (isValidUtf8(buffer)) return utf8;
    return buffer.toString(ENCODING_FALLBACK);
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

function stripMarkdownSyntax(text: string): string {
  return text
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/!\[([^\]]*)\]\([^)]+\)/g, '')
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
