import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import AdmZip from 'adm-zip';

import { EpubParser } from './epub-parser.js';

/**
 * Construye un EPUB mínimo en memoria. Generarlo en el test en vez de meter
 * un binario en el repo deja a la vista qué contiene cada archivo.
 */
function buildEpub(
  chapters: Record<string, string | Buffer>,
  container?: string,
): Buffer {
  const zip = new AdmZip();
  zip.addFile('mimetype', Buffer.from('application/epub+zip'));
  zip.addFile(
    'META-INF/container.xml',
    Buffer.from(
      container ??
        '<?xml version="1.0"?>' +
          '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">' +
          '<rootfiles><rootfile full-path="OEBPS/content.opf" ' +
          'media-type="application/oebps-package+xml"/></rootfiles></container>',
    ),
  );
  const names = Object.keys(chapters);
  const manifest = names
    .map((n, i) => `<item id="c${i}" href="${n}" media-type="application/xhtml+xml"/>`)
    .join('');
  const spine = names.map((_, i) => `<itemref idref="c${i}"/>`).join('');
  zip.addFile(
    'OEBPS/content.opf',
    Buffer.from(
      '<?xml version="1.0"?>' +
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">' +
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">' +
        '<dc:title>Libro de prueba</dc:title><dc:creator>Autora</dc:creator>' +
        '<dc:language>es</dc:language></metadata>' +
        `<manifest>${manifest}</manifest><spine>${spine}</spine></package>`,
    ),
  );
  for (const [name, content] of Object.entries(chapters)) {
    zip.addFile(`OEBPS/${name}`, typeof content === 'string' ? Buffer.from(content) : content);
  }
  return zip.toBuffer();
}

/** Ejecuta `fn` y devuelve cuánto tardó, para fijar que el parseo es lineal. */
async function timed(fn: () => Promise<unknown>): Promise<number> {
  const t0 = performance.now();
  await fn().catch(() => undefined);
  return performance.now() - t0;
}

const parser = new EpubParser();

describe('EpubParser — contenido', () => {
  it('extrae metadatos, capítulos y título de cada capítulo', async () => {
    const book = await parser.parse(
      buildEpub({
        'c1.xhtml': '<html><body><h1>Primero</h1><p>La derivada mide el cambio.</p></body></html>',
        'c2.xhtml': '<html><body><h2>Segundo</h2><p>La integral acumula.</p></body></html>',
      }),
    );

    assert.equal(book.title, 'Libro de prueba');
    assert.equal(book.author, 'Autora');
    assert.equal(book.chapters.length, 2);
    assert.equal(book.chapters[0]!.title, 'Primero');
    assert.equal(book.chapters[1]!.title, 'Segundo');
    assert.match(book.chapters[0]!.text, /La derivada mide el cambio\./);
  });

  it('quita scripts, estilos y etiquetas sin perder el texto', async () => {
    const book = await parser.parse(
      buildEpub({
        'c1.xhtml':
          '<html><head><style>p { color: red }</style></head><body>' +
          '<SCRIPT type="text/javascript">alert(1)</SCRIPT>' +
          '<p>Texto <b>visible</b>.</p></body></html>',
      }),
    );

    const text = book.chapters[0]!.text;
    assert.ok(!text.includes('alert'), 'el script no debe leerse');
    assert.ok(!text.includes('color'), 'el estilo no debe leerse');
    assert.match(text, /Texto visible\./);
  });

  it('cae en "Capítulo N" cuando no hay título', async () => {
    const book = await parser.parse(buildEpub({ 'c1.xhtml': '<p>Sin encabezado.</p>' }));
    assert.equal(book.chapters[0]!.title, 'Capítulo 1');
  });
});

describe('EpubParser — entradas hostiles', () => {
  it('rechaza una bomba de descompresión sin reservar sus gigas', async () => {
    // 20 MiB de una sola letra se comprimen a unos pocos KB: supera el tope
    // por entrada (16 MiB) sin que el archivo subido llame la atención.
    const bomb = Buffer.alloc(20 * 1024 * 1024, 0x61);

    await assert.rejects(parser.parse(buildEpub({ 'c1.xhtml': bomb })), /demasiado grande/);
  });

  it('procesa en tiempo lineal muchos <script> sin cerrar', async () => {
    // Con el patrón anterior esto tardaba del orden de un minuto.
    const html = '<p>Hola</p>' + '<script>'.repeat(200_000);
    const ms = await timed(() => parser.parse(buildEpub({ 'c1.xhtml': html })));
    assert.ok(ms < 2000, `tardó ${ms.toFixed(0)} ms`);
  });

  it('procesa en tiempo lineal muchos "<" sin ">"', async () => {
    const html = '<p>Hola</p>' + '<a'.repeat(200_000);
    const ms = await timed(() => parser.parse(buildEpub({ 'c1.xhtml': html })));
    assert.ok(ms < 2000, `tardó ${ms.toFixed(0)} ms`);
  });

  it('busca el título en tiempo lineal con muchos <h1> sin cerrar', async () => {
    const html = '<p>Hola</p>' + '<h1>'.repeat(200_000);
    const ms = await timed(() => parser.parse(buildEpub({ 'c1.xhtml': html })));
    assert.ok(ms < 2000, `tardó ${ms.toFixed(0)} ms`);
  });

  it('procesa en tiempo lineal un container.xml con DOCTYPEs sin cerrar', async () => {
    // El patrón anterior de DOCTYPE era el peor: 1,6 s con 16.000 repeticiones.
    const container = '<!DOCTYPE a'.repeat(100_000);
    const ms = await timed(() =>
      parser.parse(buildEpub({ 'c1.xhtml': '<p>Hola</p>' }, container)),
    );
    assert.ok(ms < 2000, `tardó ${ms.toFixed(0)} ms`);
  });

  it('sigue quitando un DOCTYPE con subconjunto interno', async () => {
    const container =
      '<?xml version="1.0"?><!DOCTYPE container [ <!ENTITY x "y"> ]>' +
      '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">' +
      '<rootfiles><rootfile full-path="OEBPS/content.opf" ' +
      'media-type="application/oebps-package+xml"/></rootfiles></container>';

    const book = await parser.parse(buildEpub({ 'c1.xhtml': '<p>Hola</p>' }, container));
    assert.equal(book.chapters.length, 1);
  });
});
