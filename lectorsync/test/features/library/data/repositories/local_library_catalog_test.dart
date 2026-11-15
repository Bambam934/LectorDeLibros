import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/library/data/repositories/local_library_repository.dart';
import 'package:lectorsync/features/library/domain/entities/book.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

const _id1 = '11111111-1111-4111-8111-111111111111';
const _id2 = '22222222-2222-4222-8222-222222222222';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory books;
  late Directory support;

  LocalLibraryRepository repo() => LocalLibraryRepository(
        booksDir: () async => books,
        catalogDir: () async => support,
      );

  File catalog() => File('${support.path}/library_catalog.json');

  Future<List<Book>> titles(LocalLibraryRepository r) async =>
      (await r.getBooks()).getOrElse((f) => throw f);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('catalogo');
    books = Directory('${root.path}/lectorsync_books')..createSync();
    support = Directory('${root.path}/support')..createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('lo importado se guarda en su archivo y lo ve otra instancia', () async {
    final result = await repo().importBook(
      filename: 'mi_libro.txt',
      bytes: Uint8List.fromList(utf8.encode('hola mundo')),
    );
    expect(result.isRight(), isTrue);
    expect(catalog().existsSync(), isTrue);

    final list = await titles(repo());
    expect(list.map((b) => b.title), ['Mi libro']);
    // Nada en SharedPreferences: el catálogo ya no vive ahí.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('importaciones y progreso a la vez no se pisan', () async {
    final r = repo();
    final a = await r.importBook(
        filename: 'a.txt', bytes: Uint8List.fromList([97]));
    final id = a.getOrElse((f) => throw f).id;
    await Future.wait([
      r.importBook(filename: 'b.txt', bytes: Uint8List.fromList([98])),
      r.updateBookProgress(bookId: id, progress: 0.5),
      r.importBook(filename: 'c.txt', bytes: Uint8List.fromList([99])),
    ]);

    final list = await titles(repo());
    expect(list.map((b) => b.title), ['A', 'B', 'C']);
    expect(list.first.progress, 0.5);
  });

  test('con el principal corrupto usa la copia de la escritura anterior',
      () async {
    final r = repo();
    await r.importBook(filename: 'uno.txt', bytes: Uint8List.fromList([1]));
    await r.importBook(filename: 'dos.txt', bytes: Uint8List.fromList([2]));
    catalog().writeAsStringSync('{"a medias');

    // La copia es la del primer import; «Dos» vuelve como recuperado.
    final list = await titles(repo());
    expect(list.map((b) => b.title), contains('Uno'));
    expect(list, hasLength(2));
  });

  test('migra el catálogo de SharedPreferences y conserva el progreso',
      () async {
    final path = '${books.path}${Platform.pathSeparator}$_id1.txt';
    File(path).writeAsStringSync('texto');
    SharedPreferences.setMockInitialValues({
      'local_library_books_v1': jsonEncode([
        {
          'id': _id1,
          'title': 'Cálculo integral',
          'file_format': 'txt',
          'progress': 0.4,
          'progress_word_index': 120,
          'stored_path': path,
        }
      ]),
    });

    final list = await titles(repo());
    expect(list.single.title, 'Cálculo integral');
    expect(list.single.progress, 0.4);
    expect(catalog().existsSync(), isTrue);
  });

  test('recupera los libros de la carpeta que el catálogo no conoce', () async {
    final document = PdfDocument();
    document.pages.add();
    document.documentInformation.title = 'Física moderna';
    File('${books.path}/$_id1.pdf').writeAsBytesSync(await document.save());
    document.dispose();
    File('${books.path}/$_id2.txt').writeAsStringSync('texto');
    // Ni las cachés de capítulos ni archivos ajenos son libros.
    File('${books.path}/$_id1.chapters.v13.json').writeAsStringSync('[]');
    File('${books.path}/notas.txt').writeAsStringSync('no es de la app');

    final r = repo();
    final list = await titles(r);
    expect(list, hasLength(2));
    expect(list.map((b) => b.id), containsAll([_id1, _id2]));
    expect(list.firstWhere((b) => b.id == _id1).title, 'Física moderna');
    expect(list.firstWhere((b) => b.id == _id2).title,
        startsWith('Libro recuperado ('));
    expect(await r.resolveStoredPath(_id2), endsWith('$_id2.txt'));

    // Quedan en el catálogo: la segunda lectura no los duplica.
    expect(await titles(repo()), hasLength(2));
  });
}
