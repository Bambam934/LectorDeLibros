export type ParsedChapter = {
  title: string;
  orderIndex: number;
  text: string;
  wordCount: number;
};

export type ParsedBook = {
  title: string;
  author: string | null;
  language: string;
  fileFormat: 'epub' | 'pdf' | 'txt' | 'md';
  filename?: string;
  chapters: ParsedChapter[];
  totalWords: number;
};

export type BookParser = {
  parse(buffer: Buffer, filename?: string): Promise<ParsedBook>;
};

export function countWords(text: string): number {
  return text.trim().split(/\s+/).filter(Boolean).length;
}

/** Tamaño objetivo de capítulo al dividir por conteo de palabras (formatos sin estructura). */
export const MAX_WORDS_PER_CHAPTER = 5000;
