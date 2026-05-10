import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { detectFormat, isSupportedFormat, createParser, parseBookFile } from './index.js';
import { countWords } from './types.js';

describe('parsers — format detection', () => {
  it('detects EPUB by extension', () => {
    assert.equal(detectFormat('book.epub', 'application/octet-stream'), 'epub');
  });

  it('detects EPUB by MIME type', () => {
    assert.equal(detectFormat('unknown', 'application/epub+zip'), 'epub');
  });

  it('detects PDF by extension', () => {
    assert.equal(detectFormat('document.pdf', 'application/octet-stream'), 'pdf');
  });

  it('detects PDF by MIME type', () => {
    assert.equal(detectFormat('unknown', 'application/pdf'), 'pdf');
  });

  it('detects TXT by extension', () => {
    assert.equal(detectFormat('notes.txt', 'text/plain'), 'txt');
  });

  it('detects TXT by MIME type', () => {
    assert.equal(detectFormat('unknown', 'text/plain'), 'txt');
  });

  it('detects MD by extension .md', () => {
    assert.equal(detectFormat('readme.md', 'text/plain'), 'md');
  });

  it('detects MD by extension .markdown', () => {
    assert.equal(detectFormat('readme.markdown', 'text/plain'), 'md');
  });

  it('detects MD by MIME type', () => {
    assert.equal(detectFormat('unknown', 'text/markdown'), 'md');
  });

  it('detects MD by text/x-markdown MIME', () => {
    assert.equal(detectFormat('unknown', 'text/x-markdown'), 'md');
  });

  it('returns null for unsupported format', () => {
    assert.equal(detectFormat('file.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'), null);
  });

  it('handles MIME type with charset', () => {
    assert.equal(detectFormat('f.txt', 'text/plain; charset=utf-8'), 'txt');
  });
});

describe('parsers — isSupportedFormat', () => {
  it('returns true for epub', () => assert.ok(isSupportedFormat('epub')));
  it('returns true for pdf', () => assert.ok(isSupportedFormat('pdf')));
  it('returns true for txt', () => assert.ok(isSupportedFormat('txt')));
  it('returns true for md', () => assert.ok(isSupportedFormat('md')));
  it('returns false for docx', () => assert.ok(!isSupportedFormat('docx')));
  it('returns false for null', () => assert.ok(!isSupportedFormat(null)));
});

describe('parsers — createParser', () => {
  it('creates EpubParser for epub', () => {
    const parser = createParser('epub');
    assert.equal(typeof parser.parse, 'function');
  });

  it('creates PdfParser for pdf', () => {
    const parser = createParser('pdf');
    assert.equal(typeof parser.parse, 'function');
  });

  it('creates TextParser for txt', () => {
    const parser = createParser('txt');
    assert.equal(typeof parser.parse, 'function');
  });

  it('creates TextParser for md', () => {
    const parser = createParser('md');
    assert.equal(typeof parser.parse, 'function');
  });
});

describe('parsers — TextParser', () => {
  it('parses a simple TXT file into one chapter', async () => {
    const content = 'This is a simple text file with some words in it.';
    const buffer = Buffer.from(content, 'utf-8');
    const result = await parseBookFile(buffer, 'txt');

    assert.equal(result.fileFormat, 'txt');
    assert.equal(result.chapters.length, 1);
    assert.ok(result.chapters[0]!.wordCount > 0);
    assert.equal(result.totalWords, result.chapters[0]!.wordCount);
  });

  it('splits TXT by "Capítulo" headings', async () => {
    const content = `Capítulo 1

First chapter content with some text here.

Capítulo 2

Second chapter content with more text here.`;
    const buffer = Buffer.from(content, 'utf-8');
    const result = await parseBookFile(buffer, 'txt');

    assert.equal(result.chapters.length, 2);
    assert.match(result.chapters[0]!.title, /Capítulo 1/);
    assert.match(result.chapters[1]!.title, /Capítulo 2/);
  });

  it('splits TXT by separator lines', async () => {
    const content = `First section content.

***

Second section content here.`;
    const buffer = Buffer.from(content, 'utf-8');
    const result = await parseBookFile(buffer, 'txt');

    assert.equal(result.chapters.length, 2);
  });

  it('splits TXT by word count when no headings', async () => {
    const words = Array.from({ length: 12000 }, (_, i) => `word${i}`).join(' ');
    const buffer = Buffer.from(words, 'utf-8');
    const result = await parseBookFile(buffer, 'txt');

    assert.ok(result.chapters.length >= 2, `Expected >= 2 chapters, got ${result.chapters.length}`);
    assert.equal(result.fileFormat, 'txt');
    assert.equal(result.author, null);
  });

  it('parses a Markdown file with # headings', async () => {
    const content = `# My Book Title

# Chapter One

This is the first chapter with some content.

# Chapter Two

This is the second chapter with more content.`;
    const buffer = Buffer.from(content, 'utf-8');
    const result = await parseBookFile(buffer, 'md');

    assert.equal(result.fileFormat, 'md');
    assert.ok(result.chapters.length >= 2);
  });

  it('strips Markdown syntax in md mode', async () => {
    const content = `# Title

This has **bold** and *italic* and [a link](https://example.com) text.`;
    const buffer = Buffer.from(content, 'utf-8');
    const result = await parseBookFile(buffer, 'md');

    const chapterText = result.chapters[0]!.text;
    assert.ok(!chapterText.includes('**'), 'Bold markers should be stripped');
    assert.ok(!chapterText.includes('[a link]'), 'Link syntax should be stripped');
    assert.ok(chapterText.includes('bold'), 'Bold text content should remain');
  });

  it('handles empty text gracefully', async () => {
    const buffer = Buffer.from('   \n\n  \n  ', 'utf-8');
    await assert.rejects(
      () => parseBookFile(buffer, 'txt'),
      { message: /no contiene texto/i }
    );
  });

  it('extracts title from first line in TXT', async () => {
    const content = `My Great Document

This is the content of the document.`;
    const buffer = Buffer.from(content, 'utf-8');
    const result = await parseBookFile(buffer, 'txt');

    assert.equal(result.title, 'My Great Document');
  });

  it('extracts title from # heading in Markdown', async () => {
    const content = `# My Book

Some content here.`;
    const buffer = Buffer.from(content, 'utf-8');
    const result = await parseBookFile(buffer, 'md');

    assert.equal(result.title, 'My Book');
  });
});

describe('parsers — countWords', () => {
  it('counts words correctly', () => {
    assert.equal(countWords('hello world foo'), 3);
  });

  it('handles extra whitespace', () => {
    assert.equal(countWords('  hello   world  '), 2);
  });

  it('returns 0 for empty string', () => {
    assert.equal(countWords(''), 0);
  });

  it('returns 0 for whitespace-only string', () => {
    assert.equal(countWords('   \n\t  '), 0);
  });
});
