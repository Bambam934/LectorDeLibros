import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/parsing/pdf_page_locator.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Escribe un PDF real con una línea de texto por página.
///
/// Generarlo con Syncfusion en vez de meter un fixture binario en el repo
/// mantiene el test legible: se ve qué dice cada página.
Future<File> _writePdf(Directory dir, List<String> pageTexts) async {
  final document = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 14);
  for (final text in pageTexts) {
    final page = document.pages.add();
    page.graphics.drawString(text, font);
  }
  final file = File('${dir.path}/libro.pdf');
  await file.writeAsBytes(await document.save(), flush: true);
  document.dispose();
  return file;
}

void main() {
  late Directory tempDir;
  late PdfPageLocator locator;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdf_page_locator_test');
    locator = PdfPageLocator();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('PdfPageLocator', () {
    test('encuentra la página que contiene el fragmento', () async {
      final pdf = await _writePdf(tempDir, [
        'Primera pagina de prueba',
        'La formula 2x+1=5 esta aqui',
        'Tercera pagina de prueba',
      ]);

      final page = await locator.locate(pdfPath: pdf.path, fragment: '2x+1=5');

      expect(page, 1, reason: 'índice base 0 de la segunda página');
    });

    test('ignora las diferencias de espaciado', () async {
      // El texto del capítulo pasó por el reflow y sus espacios ya no son los
      // de la extracción cruda; comparar sin espacios es lo que lo salva.
      final pdf = await _writePdf(tempDir, [
        'Sea f una funcion continua',
        'F(b) - F(a) es el resultado',
      ]);

      final page = await locator.locate(
        pdfPath: pdf.path,
        fragment: 'F(b)-F(a)   es  el resultado',
      );

      expect(page, 1);
    });

    test('no distingue mayúsculas de minúsculas', () async {
      final pdf = await _writePdf(tempDir, ['INTEGRAL DEFINIDA']);

      expect(
        await locator.locate(pdfPath: pdf.path, fragment: 'integral definida'),
        0,
      );
    });

    test('devuelve null si el fragmento no está en el documento', () async {
      final pdf = await _writePdf(tempDir, ['Una pagina cualquiera']);

      expect(
        await locator.locate(pdfPath: pdf.path, fragment: 'no existe aqui'),
        isNull,
      );
    });

    test('devuelve null si el archivo no existe', () async {
      expect(
        await locator.locate(
          pdfPath: '${tempDir.path}/fantasma.pdf',
          fragment: 'lo que sea',
        ),
        isNull,
      );
    });

    test('devuelve null si el archivo no es un PDF', () async {
      final fake = File('${tempDir.path}/libro.txt');
      await fake.writeAsString('esto no es un pdf');

      expect(
        await locator.locate(pdfPath: fake.path, fragment: 'esto'),
        isNull,
      );
    });

    test('devuelve null ante un fragmento vacío', () async {
      final pdf = await _writePdf(tempDir, ['Contenido']);

      expect(await locator.locate(pdfPath: pdf.path, fragment: '   '), isNull);
    });

    test('indexa el documento una sola vez', () async {
      final pdf = await _writePdf(tempDir, ['Primera', 'Segunda']);

      await locator.locate(pdfPath: pdf.path, fragment: 'Primera');
      expect(locator.pageCountOf(pdf.path), 2);

      // Si el índice no estuviera cacheado, borrar el fichero rompería la
      // segunda búsqueda.
      await pdf.delete();
      expect(await locator.locate(pdfPath: pdf.path, fragment: 'Segunda'), 1);
    });

    test('evict obliga a releer el documento', () async {
      final pdf = await _writePdf(tempDir, ['Primera']);
      await locator.locate(pdfPath: pdf.path, fragment: 'Primera');

      locator.evict(pdf.path);
      expect(locator.pageCountOf(pdf.path), isNull);
    });

    test('encuentra la página aunque el PDF parta la palabra con guion',
        () async {
      // El fragmento llega del capítulo, que ya pasó por el reflow y trae
      // "consumismo" de una pieza; el PDF conserva el guion del corte de
      // línea. Sin normalizar los guiones, este caso no casaba nunca.
      final pdf = await _writePdf(tempDir, [
        'Primera pagina',
        'El consu- mismo actual crece',
      ]);

      final page = await locator.locate(
        pdfPath: pdf.path,
        fragment: 'El consumismo actual crece',
      );

      expect(page, 1);
    });

    test('dos búsquedas a la vez comparten un solo indexado', () async {
      final pdf = await _writePdf(tempDir, ['Primera', 'Segunda']);

      final results = await Future.wait([
        locator.locate(pdfPath: pdf.path, fragment: 'Primera'),
        locator.locate(pdfPath: pdf.path, fragment: 'Segunda'),
      ]);

      expect(results, [0, 1]);
      expect(locator.pageCountOf(pdf.path), 2);
    });
  });

  group('normalizeForSearch', () {
    test('quita espacios, guiones y mayúsculas', () {
      expect(normalizeForSearch('F(b) - F(a)'), 'f(b)f(a)');
      expect(normalizeForSearch('consu- mismo'), 'consumismo');
      expect(normalizeForSearch('INTEGRAL  DEFINIDA'), 'integraldefinida');
    });

    test('es simétrica: capítulo y PDF crudo convergen', () {
      expect(
        normalizeForSearch('el consumismo actual'),
        normalizeForSearch('el consu- mismo actual'),
      );
    });
  });
}
