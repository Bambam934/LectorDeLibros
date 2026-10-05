import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/core/storage/local_book_store.dart';
import 'package:lectorsync/features/reader/data/parsing/ink_probe.dart';
import 'package:lectorsync/features/reader/data/repositories/local_reader_repository.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter_block.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class _FakeStore implements LocalBookStore {
  _FakeStore(this.paths);

  final Map<String, String> paths;
  int? totalChapters;
  double? progress;
  int? progressWordIndex;

  @override
  Future<String?> resolveStoredPath(String bookId) async => paths[bookId];

  @override
  Future<void> updateBookProgress({
    required String bookId,
    int? totalChapters,
    int? totalWords,
    double? progress,
    String? progressChapterId,
    int? progressWordIndex,
  }) async {
    this.totalChapters = totalChapters ?? this.totalChapters;
    this.progress = progress ?? this.progress;
    this.progressWordIndex = progressWordIndex ?? this.progressWordIndex;
  }
}

/// Simula la comprobación de tinta: hay tinta donde la prueba dibujó algo.
class _FakeInkProbe implements InkProbe {
  _FakeInkProbe(this.inkedBands);

  /// Franjas verticales (página, arriba, abajo) con algo dibujado.
  final List<(int, double, double)> inkedBands;
  final requested = <(int, PageRect)>[];

  @override
  Future<List<PageRect?>> inkBounds(
    String pdfPath,
    List<(int, PageRect)> regions,
  ) async {
    requested.addAll(regions);
    return [
      for (final (page, rect) in regions)
        _inkIn(page, rect),
    ];
  }

  PageRect? _inkIn(int page, PageRect rect) {
    for (final (p, top, bottom) in inkedBands) {
      if (p == page && top >= rect.top && bottom <= rect.bottom) {
        return PageRect(100, top, 300, bottom);
      }
    }
    return null;
  }
}

/// Un libro con prosa en Times, código en Courier con dos niveles de
/// sangría, un hueco con un rectángulo dibujado (y 230-245) y otro vacío.
Uint8List _technicalPdf() {
  final document = PdfDocument();
  final graphics = document.pages.add().graphics;
  final body = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final code = PdfStandardFont(PdfFontFamily.courier, 10);
  void line(String text, PdfFont font, double x, double y) =>
      graphics.drawString(text, font, bounds: Rect.fromLTWH(x, y, 480, 16));

  var y = 40.0;
  for (var i = 0; i < 8; i++) {
    line('Una linea de prosa del libro tecnico con varias palabras $i.', body,
        40, y);
    y += 15;
  }
  // Señal de que el libro es de matemáticas: un tramo en la fuente Symbol
  // dentro de una línea de prosa. Sin ella, la figura baja sería "Figura".
  final symbol = PdfStandardFont(PdfFontFamily.symbol, 12);
  y -= 15;
  graphics.drawString('abcdefghijklmnopqrstuvwxy', symbol,
      bounds: Rect.fromLTWH(360, y, 200, 16));
  // Hueco con tinta: una ecuación dibujada, no escrita.
  y += 15;
  graphics.drawRectangle(
    brush: PdfSolidBrush(PdfColor(0, 0, 0)),
    bounds: const Rect.fromLTWH(100, 230, 200, 15),
  );
  y = 270;
  for (var i = 0; i < 4; i++) {
    line('Otra linea de prosa tras la ecuacion dibujada $i.', body, 40, y);
    y += 15;
  }
  y += 10;
  line('def trabajo(f, d):', code, 40, y);
  line('return f * d', code, 64, y + 13);
  y += 30;
  for (var i = 0; i < 4; i++) {
    line('Prosa despues del codigo con sus palabras $i.', body, 40, y);
    y += 15;
  }
  // Hueco vacío: aire, no una figura.
  y += 40;
  for (var i = 0; i < 4; i++) {
    line('Prosa al final de la pagina con palabras $i.', body, 40, y);
    y += 15;
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

Uint8List _pdfWith(List<String> pages) {
  final document = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  for (final text in pages) {
    document.pages.add().graphics.drawString(
          text,
          font,
          bounds: const Rect.fromLTWH(0, 0, 500, 700),
        );
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

void main() {
  late Directory dir;
  final sep = Platform.pathSeparator;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lectorsync_reader_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('abre un PDF, lo cachea en v8 y borra la caché de la versión vieja',
      () async {
    final stored = '${dir.path}${sep}libro.pdf';
    await File(stored).writeAsBytes(
      _pdfWith(['Primera pagina del libro.', 'Segunda pagina del libro.']),
    );
    final stale = File('${dir.path}${sep}libro.chapters.v7.json');
    await stale.writeAsString('[]');
    final store = _FakeStore({'libro': stored});

    final result = await LocalReaderRepository(store: store).getChapters('libro');

    final chapters = result.getOrElse((f) => fail('falló: ${f.message}'));
    expect(chapters, isNotEmpty);
    expect(store.totalChapters, chapters.length);
    expect(File('${dir.path}${sep}libro.chapters.v8.json').existsSync(), isTrue);
    expect(stale.existsSync(), isFalse);

    final chapter = await LocalReaderRepository(store: store)
        .getChapter(bookId: 'libro', chapterId: chapters.first.id);
    final text = chapter.getOrElse((f) => fail('falló: ${f.message}')).text;
    expect(text, contains('Primera pagina del libro.'));
    expect(text, contains('Segunda pagina del libro.'));
  });

  test('un PDF técnico sale en bloques: código con sangría y la ecuación '
      'dibujada, sin inventar figuras en el hueco vacío', () async {
    final stored = '${dir.path}${sep}tecnico.pdf';
    await File(stored).writeAsBytes(_technicalPdf());
    final probe = _FakeInkProbe([(0, 230, 245)]);
    final repo = LocalReaderRepository(
      store: _FakeStore({'tecnico': stored}),
      inkProbe: probe,
    );

    final summaries =
        (await repo.getChapters('tecnico')).getOrElse((f) => fail(f.message));
    final chapter = (await repo.getChapter(
      bookId: 'tecnico',
      chapterId: summaries.first.id,
    ))
        .getOrElse((f) => fail(f.message));

    final kinds = chapter.blocks.map((b) => b.kind).toList();
    expect(probe.requested, hasLength(2), reason: 'dos huecos candidatos');
    expect(kinds.where((k) => k == ChapterBlockKind.figure), hasLength(1));
    final code =
        chapter.blocks.singleWhere((b) => b.kind == ChapterBlockKind.code);
    expect(code.text, 'def trabajo(f, d):\n    return f * d');
    final figure =
        chapter.blocks.singleWhere((b) => b.kind == ChapterBlockKind.figure);
    expect(figure.figureKind, FigureKind.formula);
    expect(figure.page, 0);
    // Las palabras de la figura y del código cuentan en el capítulo.
    expect(chapter.words, contains(kFormulaMarker));
    expect(chapter.words, contains('trabajo(f,'));
  });

  test('los bloques sobreviven a la caché en disco', () async {
    final stored = '${dir.path}${sep}notas.md';
    await File(stored).writeAsString(
      '# Uno\n\nTexto del primero.\n\n```python\nx = 1\n    y = 2\n```\n'
      '# Dos\n\n### Ejercicio 1\nTexto del segundo.\n',
    );
    final store = _FakeStore({'notas': stored});

    final first = LocalReaderRepository(store: store);
    final fresh = (await first.getChapters('notas'))
        .getOrElse((f) => fail(f.message));
    final parsed = (await first.getChapter(
      bookId: 'notas',
      chapterId: fresh.first.id,
    ))
        .getOrElse((f) => fail(f.message));

    // Otra instancia, sin caché en memoria: lee la caché del disco.
    final second = LocalReaderRepository(store: store);
    final cached = (await second.getChapter(
      bookId: 'notas',
      chapterId: fresh.first.id,
    ))
        .getOrElse((f) => fail(f.message));

    expect(parsed.blocks, const [
      ChapterBlock.heading('Uno'),
      ChapterBlock.paragraph('Texto del primero.'),
      ChapterBlock.code('x = 1\n    y = 2'),
    ]);
    expect(cached.blocks, parsed.blocks);
    expect(cached.words, parsed.words);
    expect(fresh.map((c) => c.title), ['Uno', 'Dos']);
  });

  test('el progreso es la palabra global entre el total, sin volver a sumar '
      'los capítulos anteriores', () async {
    final stored = '${dir.path}${sep}dos.md';
    // Dos capítulos de 4 y 6 palabras.
    await File(stored).writeAsString('# Uno\nuna dos tres\n# Dos\ncuatro '
        'cinco seis siete ocho\n');
    final store = _FakeStore({'dos': stored});
    final repo = LocalReaderRepository(store: store);
    final chapters =
        (await repo.getChapters('dos')).getOrElse((f) => fail(f.message));
    expect(chapters.map((c) => c.wordCount), [4, 6]);

    // El lector manda la palabra 7 del libro, la tercera del capítulo 2.
    await repo.saveProgress(
      bookId: 'dos',
      chapterId: chapters[1].id,
      wordIndex: 7,
    );

    expect(store.progress, closeTo(0.7, 1e-9));
    expect(store.progressWordIndex, 7);
  });

  test('abre un TXT guardado como ANSI de Windows', () async {
    final stored = '${dir.path}${sep}cuento.txt';
    // "Érase una canción…" en Windows-1252.
    await File(stored).writeAsBytes([
      0xC9, 0x72, 0x61, 0x73, 0x65, 0x20, 0x75, 0x6E, 0x61, 0x20, //
      0x63, 0x61, 0x6E, 0x63, 0x69, 0xF3, 0x6E, 0x85,
    ]);
    final repo = LocalReaderRepository(store: _FakeStore({'cuento': stored}));

    final chapters =
        (await repo.getChapters('cuento')).getOrElse((f) => fail(f.message));
    final chapter = await repo.getChapter(
      bookId: 'cuento',
      chapterId: chapters.first.id,
    );

    expect(
      chapter.getOrElse((f) => fail(f.message)).text,
      'Érase una canción…',
    );
  });
}
