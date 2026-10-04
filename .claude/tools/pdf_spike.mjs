// Spike de diseño (solo lectura): ¿qué señales de fuente y maquetación trae un PDF?
// Con él se midieron los libros del ADR 13 (2026-10-03); ver docs/PLAN-BLOQUES-TIPADOS.md.
// Usa el pdf.js del backend: hace falta `npm install` en backend/.
//
// Uso (desde la raíz del repo):
//   node .claude/tools/pdf_spike.mjs fonts <pdf>          fuentes por % de caracteres y páginas con imágenes
//   node .claude/tools/pdf_spike.mjs find <pdf> <texto>   páginas que contienen el texto
//   node .claude/tools/pdf_spike.mjs dump <pdf> <página>  líneas con posición, fuente e imágenes
import fs from 'node:fs';
import * as pdfjs from '../../backend/node_modules/pdfjs-dist/legacy/build/pdf.mjs';

const [, , mode, file, arg] = process.argv;
const data = new Uint8Array(fs.readFileSync(file));
const doc = await pdfjs.getDocument({
  data,
  isEvalSupported: false,
  disableFontFace: true,
  verbosity: 0,
}).promise;

const IMAGE_OPS = new Set([
  pdfjs.OPS.paintImageXObject,
  pdfjs.OPS.paintInlineImageXObject,
  pdfjs.OPS.paintImageMaskXObject,
]);

async function pageData(n, withOps) {
  const page = await doc.getPage(n);
  let images = 0;
  const imageRects = [];
  if (withOps) {
    const ops = await page.getOperatorList();
    // Rastrea la matriz de transformación para saber dónde cae cada imagen.
    let ctm = [1, 0, 0, 1, 0, 0];
    const stack = [];
    const mul = (m, n) => [
      m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1],
      m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
      m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5],
    ];
    for (let i = 0; i < ops.fnArray.length; i++) {
      const fn = ops.fnArray[i];
      if (fn === pdfjs.OPS.save) stack.push(ctm);
      else if (fn === pdfjs.OPS.restore) ctm = stack.pop() ?? ctm;
      else if (fn === pdfjs.OPS.transform) ctm = mul(ctm, ops.argsArray[i]);
      else if (IMAGE_OPS.has(fn)) {
        images++;
        imageRects.push({
          x: Math.round(ctm[4]), y: Math.round(ctm[5]),
          w: Math.round(Math.hypot(ctm[0], ctm[1])), h: Math.round(Math.hypot(ctm[2], ctm[3])),
        });
      }
    }
  }
  const tc = await page.getTextContent();
  const realName = (id) => {
    try {
      return page.commonObjs.get(id)?.name ?? id;
    } catch {
      return id;
    }
  };
  const items = tc.items
    .filter((it) => it.str !== undefined)
    .map((it) => ({
      str: it.str,
      font: withOps ? realName(it.fontName) : it.fontName,
      family: tc.styles[it.fontName]?.fontFamily,
      x: Math.round(it.transform[4]),
      y: Math.round(it.transform[5]),
      h: Math.round(it.height),
      eol: it.hasEOL,
    }));
  page.cleanup();
  return { items, images, imageRects };
}

if (mode === 'fonts') {
  const chars = new Map();
  const imagePages = [];
  for (let p = 1; p <= doc.numPages; p++) {
    const { items, images } = await pageData(p, true);
    for (const it of items) {
      const key = `${it.font} [${it.family}]`;
      chars.set(key, (chars.get(key) ?? 0) + it.str.length);
    }
    if (images) imagePages.push(`${p}:${images}`);
  }
  const total = [...chars.values()].reduce((a, b) => a + b, 0);
  console.log(`páginas ${doc.numPages}, caracteres ${total}`);
  for (const [k, v] of [...chars].sort((a, b) => b[1] - a[1]).slice(0, 25)) {
    console.log(`${((100 * v) / total).toFixed(1).padStart(5)} %  ${k}`);
  }
  console.log(`páginas con imágenes (${imagePages.length}): ${imagePages.slice(0, 60).join(' ')}`);
} else if (mode === 'find') {
  const needle = arg.toLowerCase();
  const hits = [];
  for (let p = 1; p <= doc.numPages; p++) {
    const { items } = await pageData(p, false);
    if (items.map((i) => i.str).join(' ').toLowerCase().includes(needle)) hits.push(p);
  }
  console.log(`"${arg}" en páginas: ${hits.join(' ')}`);
} else if (mode === 'dump') {
  const { items, images, imageRects } = await pageData(Number(arg), true);
  console.log(`página ${arg}: ${items.length} trozos, ${images} imágenes`);
  for (const r of imageRects) {
    items.push({ str: `[IMAGEN ${r.w}x${r.h}]`, font: '·', x: r.x, y: r.y + r.h, h: r.h });
  }
  const lines = new Map();
  for (const it of items) {
    if (!it.str.trim()) continue;
    const key = it.y;
    if (!lines.has(key)) lines.set(key, []);
    lines.get(key).push(it);
  }
  for (const [y, its] of [...lines].sort((a, b) => b[0] - a[0])) {
    its.sort((a, b) => a.x - b.x);
    const fonts = [...new Set(its.map((i) => i.font.replace(/^[A-Z]{6}\+/, '')))].join('|');
    const text = its.map((i) => i.str).join(' ');
    console.log(`y${String(y).padStart(4)} x${String(its[0].x).padStart(4)} h${its[0].h} ${fonts.slice(0, 40).padEnd(40)} ${text.slice(0, 110)}`);
  }
}
await doc.destroy();
