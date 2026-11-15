import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/import_limits.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/storage/chapter_cache_files.dart';
import '../../../../core/storage/local_book_store.dart';
import '../../domain/entities/book.dart';
import '../../domain/repositories/library_repository.dart';

/// Offline-first library repository.
///
/// Almacena los archivos importados en el sandbox de la app
/// (`getApplicationDocumentsDirectory()/lectorsync_books/`) y persiste el
/// catálogo como un array JSON en su propio archivo, con escritura atómica
/// y copia (antes iba en SharedPreferences, que en Windows lo perdió).
///
/// Diseñado para funcionar sin backend mientras LectorSync esté en
/// desarrollo. Cuando exista un servidor desplegado, esta implementación
/// puede coexistir con [RemoteLibraryRepository] detrás de un toggle.
class LocalLibraryRepository implements LibraryRepository, LocalBookStore {
  /// [booksDir] y [catalogDir] solo se pasan en las pruebas.
  LocalLibraryRepository({
    Uuid? uuid,
    Future<Directory> Function()? booksDir,
    Future<Directory> Function()? catalogDir,
  })  : _uuid = uuid ?? const Uuid(),
        _booksDir = booksDir ?? _defaultBooksDir,
        _catalogDir = catalogDir ?? getApplicationSupportDirectory;

  /// Tamaño máximo de un libro importado: 50 MiB, el mismo límite que el
  /// backend (V-12, `fileSize` en `backend/src/app.ts`).
  static const maxImportBytes = kMaxImportBytes;

  /// Clave del catálogo antiguo en SharedPreferences, solo para migrarlo.
  static const _prefsKey = 'local_library_books_v1';
  static const _booksDirName = 'lectorsync_books';

  /// El catálogo vive en la carpeta de soporte de la app (en Windows,
  /// AppData; no Documentos, que OneDrive sincroniza y duplica en conflicto).
  static const _catalogName = 'library_catalog.json';
  static const _backupSuffix = '.bak';

  /// Nombre con que [importBook] guarda los archivos: `{uuid}.{ext}`.
  static final _storedName = RegExp(
    r'^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.(pdf|txt|md|epub)$',
    caseSensitive: false,
  );

  final Uuid _uuid;
  final Future<Directory> Function() _booksDir;
  final Future<Directory> Function() _catalogDir;
  Future<void> _queue = Future.value();

  static Future<Directory> _defaultBooksDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}$_booksDirName');
  }

  @override
  Future<Either<Failure, List<Book>>> getBooks() async {
    try {
      final books = await _serialized(_readCatalog);
      // Orden estable por título para que la UI no salte al refrescar.
      books.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      return Right(books);
    } catch (e) {
      return Left(ServerFailure('No se pudo leer la biblioteca local: $e'));
    }
  }

  @override
  Future<Either<Failure, Book>> importBook({
    required String filename,
    required Uint8List bytes,
  }) async {
    try {
      final format = _detectFormat(filename);
      if (format == null) {
        return Left(FileFailure(
          'Formato no soportado. Usa PDF, TXT, MD o EPUB.',
        ));
      }
      if (bytes.length > maxImportBytes) {
        return Left(FileFailure(
          'El archivo pesa más de 50 MB, el máximo para importar.',
        ));
      }

      final id = _uuid.v4();
      final dir = await _ensureBooksDir();
      final ext = _extensionFor(format);
      final storedPath = '${dir.path}${Platform.pathSeparator}$id.$ext';

      // Guardamos el archivo bruto en el sandbox de la app.
      await File(storedPath).writeAsBytes(bytes, flush: true);

      final title = _deriveTitle(filename);
      final book = Book(
        id: id,
        title: title,
        author: null,
        coverUrl: null,
        fileFormat: format,
        totalChapters: 0, // se calcula al abrir el libro
        totalWords: 0,
        progress: 0.0,
      );

      // Persistimos metadata del libro junto con el path local del archivo.
      await _serialized(() async {
        final entries = await _readRawEntries();
        // La recuperación de huérfanos pudo darlo ya de alta con otro título.
        entries.removeWhere((e) => e.book.id == id);
        entries.add(_LocalBookEntry(book: book, storedPath: storedPath));
        await _writeRawEntries(entries);
      });

      return Right(book);
    } catch (e) {
      return Left(ServerFailure('No se pudo importar el libro: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> deleteBook(String id) async {
    try {
      return await _serialized(() async {
        final entries = await _readRawEntries();
        final idx = entries.indexWhere((e) => e.book.id == id);
        if (idx < 0) {
          return Left(ServerFailure('El libro no existe en la biblioteca local.'));
        }
        final entry = entries.removeAt(idx);

        // Borrar el archivo físico — no es crítico si falla, aunque el libro
        // volverá a aparecer como recuperado.
        try {
          final file = File(entry.storedPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
        // Y sus cachés de capítulos, que si no quedaban huérfanas para siempre.
        await deleteChapterCaches(entry.storedPath);

        await _writeRawEntries(entries);
        return const Right(true);
      });
    } catch (e) {
      return Left(ServerFailure('No se pudo eliminar el libro: $e'));
    }
  }

  /// Devuelve la ruta absoluta del archivo de un libro persistido.
  /// Usado por el lector offline para abrir el contenido.
  @override
  Future<String?> resolveStoredPath(String bookId) => _serialized(() async {
        final entries = await _readRawEntries();
        for (final e in entries) {
          if (e.book.id == bookId) return e.storedPath;
        }
        return null;
      });

  /// Actualiza el progreso y/o chapter count en el catálogo local.
  /// Llamado por el lector offline cuando se descubren capítulos
  /// o se guarda progreso de lectura.
  @override
  Future<void> updateBookProgress({
    required String bookId,
    int? totalChapters,
    int? totalWords,
    double? progress,
    String? progressChapterId,
    int? progressWordIndex,
  }) =>
      _serialized(() async {
    final entries = await _readRawEntries();
    final idx = entries.indexWhere((e) => e.book.id == bookId);
    if (idx < 0) return;
    final old = entries[idx].book;
    entries[idx] = _LocalBookEntry(
      book: Book(
        id: old.id,
        title: old.title,
        author: old.author,
        coverUrl: old.coverUrl,
        fileFormat: old.fileFormat,
        totalChapters: totalChapters ?? old.totalChapters,
        totalWords: totalWords ?? old.totalWords,
        progress: progress ?? old.progress,
        progressChapterId: progressChapterId ?? old.progressChapterId,
        progressWordIndex: progressWordIndex ?? old.progressWordIndex,
      ),
      storedPath: entries[idx].storedPath,
    );
    await _writeRawEntries(entries);
      });

  // ---------- helpers ----------

  Future<Directory> _ensureBooksDir() async {
    final dir = await _booksDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<Book>> _readCatalog() async {
    final entries = await _readRawEntries();
    return entries.map((e) => e.book).toList(growable: false);
  }

  /// Pone [action] en fila detrás de las anteriores: cada leer-modificar-
  /// escribir del catálogo termina antes de que empiece el siguiente, así
  /// guardar el progreso mientras se importa no pierde ninguno de los dos.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<File> _catalogFile() async {
    final dir = await _catalogDir();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$_catalogName');
  }

  /// Lee el catálogo del disco en cada llamada, sin caché en memoria: con
  /// SharedPreferences, una segunda instancia de la app con su caché vieja
  /// reescribía el archivo entero y borraba lo que la otra había guardado.
  ///
  /// Si el principal falta o está corrupto, usa la copia de la escritura
  /// anterior; si no hay ninguno, migra el de SharedPreferences. Al final
  /// añade los libros que están en la carpeta pero no en el catálogo.
  Future<List<_LocalBookEntry>> _readRawEntries() async {
    final file = await _catalogFile();
    final entries = await _parseCatalog(file) ??
        await _parseCatalog(File('${file.path}$_backupSuffix')) ??
        await _migrateFromPrefs() ??
        <_LocalBookEntry>[];
    await _recoverOrphans(entries);
    return entries;
  }

  Future<List<_LocalBookEntry>?> _parseCatalog(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) throw const FormatException('no es una lista');
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_LocalBookEntry.fromJson)
          .toList();
    } catch (e) {
      debugPrint('[LocalLibrary] catálogo ilegible ${file.path}: $e');
      return null;
    }
  }

  Future<List<_LocalBookEntry>?> _migrateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final entries = decoded
          .whereType<Map<String, dynamic>>()
          .map(_LocalBookEntry.fromJson)
          .toList();
      // La clave vieja se deja como estaba: si algo sale mal, sigue ahí.
      await _writeRawEntries(entries);
      debugPrint('[LocalLibrary] catálogo migrado: ${entries.length} libros');
      return entries;
    } catch (_) {
      return null;
    }
  }

  /// Escritura atómica: el JSON va a un temporal y se renombra encima del
  /// principal, que antes pasa a ser la copia. Un corte a mitad deja como
  /// mucho el temporal a medias; el principal o la copia siguen enteros.
  Future<void> _writeRawEntries(List<_LocalBookEntry> entries) async {
    final file = await _catalogFile();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList(growable: false)),
      flush: true,
    );
    if (await file.exists()) await file.rename('${file.path}$_backupSuffix');
    await tmp.rename(file.path);
  }

  /// Da de alta los libros de la carpeta que el catálogo no conoce: es lo
  /// que queda cuando el catálogo se pierde. Solo cuentan los archivos que
  /// la app guardó (`{uuid}.{ext}`); las cachés de capítulos no.
  Future<void> _recoverOrphans(List<_LocalBookEntry> entries) async {
    final Directory dir;
    try {
      dir = await _booksDir();
      if (!await dir.exists()) return;
    } catch (_) {
      return; // Sin carpeta de documentos (pruebas): nada que recuperar.
    }
    final known = {
      for (final e in entries) _fileName(e.storedPath).toLowerCase(),
    };
    final recovered = <_LocalBookEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final match = _storedName.firstMatch(_fileName(entity.path));
      if (match == null || known.contains(_fileName(entity.path).toLowerCase())) {
        continue;
      }
      final format = _detectFormat(entity.path)!;
      final title = (format == BookFormat.pdf ? await _pdfTitle(entity.path) : null) ??
          'Libro recuperado (${_date(await entity.lastModified())})';
      recovered.add(_LocalBookEntry(
        book: Book(
          id: match.group(1)!,
          title: title,
          author: null,
          coverUrl: null,
          fileFormat: format,
          totalChapters: 0,
          totalWords: 0,
          progress: 0.0,
        ),
        storedPath: entity.path,
      ));
    }
    if (recovered.isEmpty) return;
    entries.addAll(recovered);
    await _writeRawEntries(entries);
    debugPrint('[LocalLibrary] recuperados ${recovered.length} libros sin catálogo');
  }

  static String _fileName(String path) =>
      path.substring(path.lastIndexOf(RegExp(r'[\\/]')) + 1);

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Título de los metadatos del PDF, en un isolate: puede pesar 50 MB.
  static Future<String?> _pdfTitle(String path) async {
    try {
      final title = await Isolate.run(() {
        final document = PdfDocument(inputBytes: File(path).readAsBytesSync());
        try {
          return document.documentInformation.title;
        } finally {
          document.dispose();
        }
      });
      final trimmed = title.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  BookFormat? _detectFormat(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => BookFormat.pdf,
      'txt' => BookFormat.txt,
      'md' || 'markdown' => BookFormat.md,
      'epub' => BookFormat.epub,
      _ => null,
    };
  }

  String _extensionFor(BookFormat format) => switch (format) {
        BookFormat.pdf => 'pdf',
        BookFormat.txt => 'txt',
        BookFormat.md => 'md',
        BookFormat.epub => 'epub',
      };

  String _deriveTitle(String filename) {
    // Sin extensión, guiones bajos → espacios, primera letra mayúscula.
    var base = filename;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    base = base.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    if (base.isEmpty) return 'Sin título';
    return base[0].toUpperCase() + base.substring(1);
  }
}

/// Entrada interna del catálogo local: libro + path absoluto del archivo.
class _LocalBookEntry {
  _LocalBookEntry({required this.book, required this.storedPath});

  factory _LocalBookEntry.fromJson(Map<String, dynamic> json) {
    return _LocalBookEntry(
      book: Book(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? 'Sin título',
        author: json['author'] as String?,
        coverUrl: json['cover_url'] as String?,
        fileFormat: BookFormat.values.firstWhere(
          (e) => e.name == (json['file_format'] as String? ?? 'pdf'),
          orElse: () => BookFormat.pdf,
        ),
        totalChapters: (json['total_chapters'] as int?) ?? 0,
        totalWords: (json['total_words'] as int?) ?? 0,
        progress: ((json['progress'] as num?) ?? 0.0).toDouble(),
        progressChapterId: json['progress_chapter_id'] as String?,
        progressWordIndex: (json['progress_word_index'] as int?) ?? 0,
      ),
      storedPath: json['stored_path'] as String,
    );
  }

  final Book book;
  final String storedPath;

  Map<String, dynamic> toJson() => {
        'id': book.id,
        'title': book.title,
        'author': book.author,
        'cover_url': book.coverUrl,
        'file_format': book.fileFormat.name,
        'total_chapters': book.totalChapters,
        'total_words': book.totalWords,
        'progress': book.progress,
        'progress_chapter_id': book.progressChapterId,
        'progress_word_index': book.progressWordIndex,
        'stored_path': storedPath,
      };
}
