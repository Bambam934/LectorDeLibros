import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/storage/chapter_cache_files.dart';
import '../../../../core/storage/local_book_store.dart';
import '../../domain/entities/book.dart';
import '../../domain/repositories/library_repository.dart';

/// Offline-first library repository.
///
/// Almacena los archivos importados en el sandbox de la app
/// (`getApplicationDocumentsDirectory()/lectorsync_books/`) y persiste el
/// catálogo en SharedPreferences como un único array JSON.
///
/// Diseñado para funcionar sin backend mientras LectorSync esté en
/// desarrollo. Cuando exista un servidor desplegado, esta implementación
/// puede coexistir con [RemoteLibraryRepository] detrás de un toggle.
class LocalLibraryRepository implements LibraryRepository, LocalBookStore {
  LocalLibraryRepository({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  /// Tamaño máximo de un libro importado: 50 MiB, el mismo límite que el
  /// backend (V-12, `fileSize` en `backend/src/app.ts`).
  static const maxImportBytes = 50 * 1024 * 1024;

  static const _prefsKey = 'local_library_books_v1';
  static const _booksDirName = 'lectorsync_books';

  final Uuid _uuid;

  @override
  Future<Either<Failure, List<Book>>> getBooks() async {
    try {
      final books = await _readCatalog();
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
      final entries = await _readRawEntries();
      entries.add(_LocalBookEntry(book: book, storedPath: storedPath));
      await _writeRawEntries(entries);

      return Right(book);
    } catch (e) {
      return Left(ServerFailure('No se pudo importar el libro: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> deleteBook(String id) async {
    try {
      final entries = await _readRawEntries();
      final idx = entries.indexWhere((e) => e.book.id == id);
      if (idx < 0) {
        return Left(ServerFailure('El libro no existe en la biblioteca local.'));
      }
      final entry = entries.removeAt(idx);

      // Borrar el archivo físico — no es crítico si falla (huérfano).
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
    } catch (e) {
      return Left(ServerFailure('No se pudo eliminar el libro: $e'));
    }
  }

  /// Devuelve la ruta absoluta del archivo de un libro persistido.
  /// Usado por el lector offline para abrir el contenido.
  @override
  Future<String?> resolveStoredPath(String bookId) async {
    final entries = await _readRawEntries();
    for (final e in entries) {
      if (e.book.id == bookId) return e.storedPath;
    }
    return null;
  }

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
  }) async {
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
  }

  // ---------- helpers ----------

  Future<Directory> _ensureBooksDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}$_booksDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<Book>> _readCatalog() async {
    final entries = await _readRawEntries();
    return entries.map((e) => e.book).toList(growable: false);
  }

  Future<List<_LocalBookEntry>> _readRawEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_LocalBookEntry.fromJson)
          .toList();
    } catch (_) {
      // Corrupto: reseteamos silenciosamente para no bloquear al usuario.
      return [];
    }
  }

  Future<void> _writeRawEntries(List<_LocalBookEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      entries.map((e) => e.toJson()).toList(growable: false),
    );
    await prefs.setString(_prefsKey, encoded);
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
