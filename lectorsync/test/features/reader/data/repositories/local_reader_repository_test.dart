import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/core/storage/local_book_store.dart';
import 'package:lectorsync/features/reader/data/repositories/local_reader_repository.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class _FakeStore implements LocalBookStore {
  _FakeStore(this.paths);

  final Map<String, String> paths;
  int? totalChapters;

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
  }
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

  test('abre un PDF, lo cachea en v4 y borra la caché de la versión vieja',
      () async {
    final stored = '${dir.path}${sep}libro.pdf';
    await File(stored).writeAsBytes(
      _pdfWith(['Primera pagina del libro.', 'Segunda pagina del libro.']),
    );
    final stale = File('${dir.path}${sep}libro.chapters.v3.json');
    await stale.writeAsString('[]');
    final store = _FakeStore({'libro': stored});

    final result = await LocalReaderRepository(store: store).getChapters('libro');

    final chapters = result.getOrElse((f) => fail('falló: ${f.message}'));
    expect(chapters, isNotEmpty);
    expect(store.totalChapters, chapters.length);
    expect(File('${dir.path}${sep}libro.chapters.v4.json').existsSync(), isTrue);
    expect(stale.existsSync(), isFalse);

    final chapter = await LocalReaderRepository(store: store)
        .getChapter(bookId: 'libro', chapterId: chapters.first.id);
    final text = chapter.getOrElse((f) => fail('falló: ${f.message}')).text;
    expect(text, contains('Primera pagina del libro.'));
    expect(text, contains('Segunda pagina del libro.'));
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
