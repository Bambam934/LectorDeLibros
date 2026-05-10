import type { BookParser, ParsedBook } from './types.js';
import { EpubParser } from './epub-parser.js';
import { PdfParser } from './pdf-parser.js';
import { TextParser } from './text-parser.js';

export type { ParsedChapter, ParsedBook, BookParser } from './types.js';

export type FileFormat = 'epub' | 'pdf' | 'txt' | 'md';

const SUPPORTED_FORMATS: FileFormat[] = ['epub', 'pdf', 'txt', 'md'];

const MIME_MAP: Record<string, FileFormat> = {
  'application/epub+zip': 'epub',
  'application/pdf': 'pdf',
  'text/plain': 'txt',
  'text/markdown': 'md',
  'text/x-markdown': 'md'
};

const EXT_MAP: Record<string, FileFormat> = {
  '.epub': 'epub',
  '.pdf': 'pdf',
  '.txt': 'txt',
  '.md': 'md',
  '.markdown': 'md'
};

const MAGIC_BYTES: Record<FileFormat, [number[], string]> = {
  epub: [[0x50, 0x4b, 0x03, 0x04], 'ZIP/EPUB'],
  pdf: [[0x25, 0x50, 0x44, 0x46], 'PDF'],
  txt: [[], 'text'],
  md: [[], 'text']
};

export function detectFormat(filename: string, mimetype: string): FileFormat | null {
  const ext = filename.match(/\.[^.]+$/)?.[0]?.toLowerCase();
  if (ext && ext in EXT_MAP) return EXT_MAP[ext]!;

  const normalisedMime = mimetype.toLowerCase().split(';')[0]!.trim();
  if (normalisedMime in MIME_MAP) return MIME_MAP[normalisedMime]!;

  return null;
}

export function validateMagicBytes(buffer: Buffer, format: FileFormat): boolean {
  if (format === 'txt' || format === 'md') {
    try {
      const text = buffer.toString('utf-8');
      return text.length > 0 && text.length <= buffer.length * 2;
    } catch {
      return false;
    }
  }

  const [expected, _name] = MAGIC_BYTES[format];
  if (expected.length === 0) return true;

  return expected.every((byte, i) => buffer[i] === byte);
}

export function isSupportedFormat(format: string | null): format is FileFormat {
  return format !== null && (SUPPORTED_FORMATS as readonly string[]).includes(format);
}

export function createParser(format: FileFormat): BookParser {
  switch (format) {
    case 'epub':
      return new EpubParser();
    case 'pdf':
      return new PdfParser();
    case 'txt':
      return new TextParser('txt');
    case 'md':
      return new TextParser('md');
  }
}

export async function parseBookFile(
  buffer: Buffer,
  format: FileFormat,
  filename?: string
): Promise<ParsedBook> {
  if (!validateMagicBytes(buffer, format)) {
    throw new Error('El contenido del archivo no corresponde con su extensión.');
  }
  const parser = createParser(format);
  return parser.parse(buffer, filename);
}
