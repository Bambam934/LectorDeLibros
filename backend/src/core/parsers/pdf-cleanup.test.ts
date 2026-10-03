import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { cleanPdfPages, reflowPageText, stripIndexEntries } from './pdf-cleanup.js';

describe('pdf-cleanup — reflowPageText', () => {
  it('une la palabra partida por el corte de línea', () => {
    assert.equal(reflowPageText('el consu- mismo actual'), 'el consumismo actual');
  });

  it('no toca los guiones legítimos', () => {
    assert.equal(reflowPageText('teórico-práctico'), 'teórico-práctico');
    assert.equal(reflowPageText('páginas 20 - 25'), 'páginas 20 - 25');
  });

  it('no une cuando la siguiente palabra empieza en mayúscula', () => {
    // "Sur- América" es un corte plausible, pero también lo es un guion
    // intencional antes de un nombre propio: preferimos no tocarlo.
    assert.equal(reflowPageText('Sur- América'), 'Sur- América');
  });

  it('colapsa los espacios sobrantes que deja pdfjs', () => {
    assert.equal(reflowPageText('  la   derivada    de  '), 'la derivada de');
  });
});

describe('pdf-cleanup — stripIndexEntries', () => {
  it('quita las entradas con relleno de puntos', () => {
    const page = 'Capítulo 1 .......... 19 Capítulo 2 ......... 25';
    assert.equal(stripIndexEntries(page), '');
  });

  it('conserva el texto que comparte página con el índice', () => {
    const page = 'Capítulo 1 .......... 19 Aquí empieza el libro.';
    assert.equal(stripIndexEntries(page), 'Aquí empieza el libro.');
  });

  it('no confunde una elipsis con relleno de puntos', () => {
    const page = 'Y entonces... 42 sigue siendo la respuesta.';
    assert.equal(stripIndexEntries(page), page);
  });

  it('procesa en tiempo lineal una racha enorme de puntos sin número', () => {
    // Regresión de seguridad (2026-10-03): `\.{5,}` se tragaba la racha,
    // fallaba en `\d` y retrocedía desde cada posición. 32.000 puntos ya
    // bloqueaban el event loop 1,7 s; 200.000 eran más de un minuto.
    const t0 = performance.now();
    const out = stripIndexEntries('.'.repeat(200_000));
    const ms = performance.now() - t0;

    assert.ok(ms < 500, `tardó ${ms.toFixed(0)} ms`);
    assert.equal(out, '.....');
  });

  it('sigue quitando un índice con relleno largo de puntos', () => {
    const page = `Capítulo 1 ${'.'.repeat(300)} 19 Aquí empieza el libro.`;
    assert.equal(stripIndexEntries(page), 'Aquí empieza el libro.');
  });
});

describe('pdf-cleanup — cleanPdfPages', () => {
  it('recorta el encabezado repetido en al menos 3 páginas', () => {
    const pages = [
      'FERNANDO ARAUJO RODRÍGUEZ20 La derivada mide el cambio.',
      'FERNANDO ARAUJO RODRÍGUEZ21 La integral acumula.',
      'FERNANDO ARAUJO RODRÍGUEZ22 El límite se aproxima.',
    ];

    assert.deepEqual(cleanPdfPages(pages), [
      'La derivada mide el cambio.',
      'La integral acumula.',
      'El límite se aproxima.',
    ]);
  });

  it('respeta un título en mayúsculas que aparece una sola vez', () => {
    const pages = [
      'INTEGRAL DEFINIDA81 Contenido del capítulo.',
      'Texto normal de la siguiente página.',
    ];

    assert.deepEqual(cleanPdfPages(pages), [
      'INTEGRAL DEFINIDA81 Contenido del capítulo.',
      'Texto normal de la siguiente página.',
    ]);
  });

  it('preserva la cardinalidad del array aunque una página quede vacía', () => {
    const pages = [
      'Índice general',
      'Capítulo 1 .......... 19 Capítulo 2 ......... 25',
      'Aquí empieza el primer capítulo.',
    ];

    const cleaned = cleanPdfPages(pages);
    assert.equal(cleaned.length, 3);
    assert.equal(cleaned[1], '');
    assert.equal(cleaned[2], 'Aquí empieza el primer capítulo.');
  });

  it('aplica reflow y recorte de encabezado en la misma pasada', () => {
    const pages = [
      'CÁLCULO INTEGRAL10 el consu- mismo',
      'CÁLCULO INTEGRAL11 otra   página',
      'CÁLCULO INTEGRAL12 y una más',
    ];

    assert.deepEqual(cleanPdfPages(pages), [
      'el consumismo',
      'otra página',
      'y una más',
    ]);
  });

  it('devuelve el array intacto cuando no hay ruido', () => {
    const pages = ['Primera página limpia.', 'Segunda página limpia.'];
    assert.deepEqual(cleanPdfPages(pages), pages);
  });

  it('NO borra los encabezados de capítulo aunque se repitan', () => {
    // Regresión: la clase perezosa del grupo incluía el espacio, así que
    // "CAPÍTULO 1" casaba con el grupo "CAPÍTULO " y tres capítulos abriendo
    // página bastaban para que se borrara el encabezado real de todos. Como
    // `splitHeuristically` busca líneas que empiecen por "Capítulo", el libro
    // se quedaba sin capítulos detectables.
    const pages = [
      'CAPÍTULO 1 La derivada mide el cambio.',
      'CAPÍTULO 2 La integral acumula.',
      'CAPÍTULO 3 El límite se aproxima.',
    ];

    assert.deepEqual(cleanPdfPages(pages), pages);
  });

  it('distingue la numeración del libro del número de página pegado', () => {
    // Separado por espacio = numeración del autor, se conserva.
    // Pegado al encabezado = número de página del extractor, se recorta.
    const numbered = [
      'TEOREMA 4 de la media.',
      'TEOREMA 5 de Rolle.',
      'TEOREMA 6 fundamental.',
    ];
    assert.deepEqual(cleanPdfPages(numbered), numbered);

    const running = [
      'ALGEBRA LINEAL204 Vectores propios.',
      'ALGEBRA LINEAL205 Diagonalización.',
      'ALGEBRA LINEAL206 Formas cuadráticas.',
    ];
    assert.deepEqual(cleanPdfPages(running), [
      'Vectores propios.',
      'Diagonalización.',
      'Formas cuadráticas.',
    ]);
  });
});
