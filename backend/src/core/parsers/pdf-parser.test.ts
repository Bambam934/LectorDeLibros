import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { MAX_PDF_PAGES, PdfParser } from './pdf-parser.js';

/** PDF mínimo válido (xref con offsets reales), una línea de texto por página. */
function buildPdf(pageTexts: string[]): Buffer {
  const objects: string[] = [];
  const pageIds: number[] = [];
  // 1: catálogo, 2: páginas, 3: fuente; después, página + contenido por cada una.
  const fontId = 3;
  let nextId = 4;
  const pageObjects: Array<[number, string]> = [];
  for (const text of pageTexts) {
    const pageId = nextId++;
    const contentId = nextId++;
    pageIds.push(pageId);
    const stream = `BT /F1 12 Tf 72 720 Td (${text}) Tj ET`;
    pageObjects.push([
      pageId,
      `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 ${fontId} 0 R >> >> /Contents ${contentId} 0 R >>`
    ]);
    pageObjects.push([contentId, `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`]);
  }
  objects[1] = '<< /Type /Catalog /Pages 2 0 R >>';
  objects[2] = `<< /Type /Pages /Kids [${pageIds.map((id) => `${id} 0 R`).join(' ')}] /Count ${pageIds.length} >>`;
  objects[fontId] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';
  for (const [id, body] of pageObjects) objects[id] = body;

  let out = '%PDF-1.4\n';
  const offsets: number[] = [];
  for (let id = 1; id < objects.length; id++) {
    offsets[id] = Buffer.byteLength(out, 'latin1');
    out += `${id} 0 obj\n${objects[id]}\nendobj\n`;
  }
  const xrefAt = Buffer.byteLength(out, 'latin1');
  out += `xref\n0 ${objects.length}\n0000000000 65535 f \n`;
  for (let id = 1; id < objects.length; id++) {
    out += `${String(offsets[id]).padStart(10, '0')} 00000 n \n`;
  }
  out += `trailer\n<< /Size ${objects.length} /Root 1 0 R >>\nstartxref\n${xrefAt}\n%%EOF\n`;
  return Buffer.from(out, 'latin1');
}

describe('PdfParser con pdfjs-dist', () => {
  it('extrae el texto de un PDF real', async () => {
    const pdf = buildPdf(['Hola mundo desde un PDF de prueba', 'Segunda pagina con texto']);
    const book = await new PdfParser().parse(pdf, 'mi-libro.pdf');
    const allText = book.chapters.map((c) => c.text).join(' ');
    assert.match(allText, /Hola mundo/);
    assert.match(allText, /Segunda pagina/);
    assert.equal(book.fileFormat, 'pdf');
  });

  it(`rechaza PDFs de más de ${MAX_PDF_PAGES} páginas`, async () => {
    const pdf = buildPdf(Array.from({ length: MAX_PDF_PAGES + 1 }, (_, i) => `p${i}`));
    await assert.rejects(new PdfParser().parse(pdf), /límite de 3000 páginas/);
  });
});
