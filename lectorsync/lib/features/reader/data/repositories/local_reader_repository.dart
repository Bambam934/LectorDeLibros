import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/storage/local_book_store.dart';
import '../../domain/entities/chapter.dart';
import '../../domain/entities/chapter_audio.dart';
import '../../domain/repositories/reader_repository.dart';

/// Offline-first reader repository.
///
/// Lee los archivos persistidos por el store local y los parsea
/// en capítulos según el formato:
///
/// - **PDF**: usa Syncfusion PdfTextExtractor para extraer texto y lo
///   divide en capítulos por tamaño (~3000 palabras cada uno).
/// - **TXT / MD**: lee el archivo como UTF-8 e intenta detectar encabezados
///   ("Capítulo X", "Chapter X", "# Título" en markdown) para los cortes.
///   Si no encuentra estructura, cae al modo por tamaño.
/// - **EPUB**: no soportado en esta primera iteración offline; devuelve
///   un error informativo.
///
/// Cachea los capítulos parseados en `{bookId}.chapters.json` junto al
/// archivo para evitar re-procesar PDFs grandes en cada apertura.
///
/// Para [getChapterAudio] no devolvemos audioUrl: el flujo de audio
/// offline usa el TTS del dispositivo (DeviceTtsRepository) que solo
/// necesita el texto del capítulo.
class LocalReaderRepository implements ReaderRepository {
  LocalReaderRepository({required LocalBookStore store})
      : _store = store;

  final LocalBookStore _store;

  // Tamaño objetivo de cada capítulo cuando no hay estructura natural.
  static const _targetWordsPerChapter = 3000;

  // Cache en memoria por libro para no leer disco en cada navegación.
  final Map<String, List<Chapter>> _memoryCache = {};

  @override
  Future<Either<Failure, List<Chapter>>> getChapters(String bookId) async {
    try {
      final chapters = await _loadOrParseChapters(bookId);
      // Devolvemos solo summaries (sin texto completo) para que la lista
      // de capítulos sea ligera en la UI.
      final summaries = chapters
          .map((c) => Chapter(
                id: c.id,
                title: c.title,
                orderIndex: c.orderIndex,
                wordCount: c.wordCount,
              ))
          .toList(growable: false);
      return Right(summaries);
    } on _ReaderError catch (e) {
      return Left(e.toFailure());
    } catch (e) {
      return Left(FileFailure('No se pudo leer el libro: $e'));
    }
  }

  @override
  Future<Either<Failure, Chapter>> getChapter({
    required String bookId,
    required String chapterId,
  }) async {
    try {
      final chapters = await _loadOrParseChapters(bookId);
      final chapter = chapters.firstWhere(
        (c) => c.id == chapterId,
        orElse: () => throw _ReaderError(
          FileFailure('Capítulo no encontrado.'),
        ),
      );
      // Reconstruimos con la lista de palabras tokenizada (igual que el
      // remote repository hace en fromDetailJson).
      return Right(Chapter(
        id: chapter.id,
        title: chapter.title,
        orderIndex: chapter.orderIndex,
        wordCount: chapter.wordCount,
        text: chapter.text,
        words: _tokenize(chapter.text ?? ''),
      ));
    } on _ReaderError catch (e) {
      return Left(e.toFailure());
    } catch (e) {
      return Left(FileFailure('No se pudo leer el capítulo: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> saveProgress({
    required String bookId,
    required String chapterId,
    required int wordIndex,
  }) async {
    try {
      final chapters = await _loadOrParseChapters(bookId);
      final totalWords = chapters.fold<int>(0, (sum, c) => sum + c.wordCount);
      // Cálculo simple de % completado: palabras leídas hasta este chapter
      // más el wordIndex dentro del actual.
      var wordsBefore = 0;
      for (final c in chapters) {
        if (c.id == chapterId) break;
        wordsBefore += c.wordCount;
      }
      final progress = totalWords == 0
          ? 0.0
          : ((wordsBefore + wordIndex) / totalWords).clamp(0.0, 1.0);

      await _store.updateBookProgress(
        bookId: bookId,
        progress: progress,
        progressChapterId: chapterId,
        progressWordIndex: wordIndex,
      );
      return const Right(true);
    } catch (e) {
      return Left(CacheFailure('No se pudo guardar el progreso: $e'));
    }
  }

  @override
  Future<Either<Failure, ChapterAudio>> getChapterAudio({
    required String bookId,
    required String chapterId,
    String voiceId = '21m00Tcm4TlvDq8ikWAW',
    String provider = 'mock',
  }) async {
    // En modo offline no hay URL de audio remoto. El TTS del dispositivo
    // sintetiza desde `chapter.text` directamente; aquí solo devolvemos
    // un descriptor vacío para que el flujo no rompa.
    return Right(ChapterAudio(
      chapterId: chapterId,
      provider: 'device-local',
    ));
  }

  // ---------- internal: parsing + cache ----------

  Future<List<Chapter>> _loadOrParseChapters(String bookId) async {
    // 1) Cache en memoria.
    final cached = _memoryCache[bookId];
    if (cached != null) return cached;

    // 2) Cache en disco.
    final storedPath = await _store.resolveStoredPath(bookId);
    if (storedPath == null) {
      throw _ReaderError(FileFailure(
        'Archivo del libro no encontrado en el dispositivo.',
      ));
    }
    final cachePath = _chaptersCachePathFor(storedPath);
    final cacheFile = File(cachePath);
    if (await cacheFile.exists()) {
      try {
        final raw = await cacheFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final chapters = decoded
              .whereType<Map<String, dynamic>>()
              .map(_chapterFromJson)
              .toList(growable: false);
          _memoryCache[bookId] = chapters;
          return chapters;
        }
      } catch (_) {
        // Cache corrupto: re-procesamos abajo.
      }
    }

    // 3) Parsear desde el archivo original.
    final file = File(storedPath);
    if (!await file.exists()) {
      throw _ReaderError(FileFailure(
        'El archivo del libro fue eliminado del dispositivo.',
      ));
    }

    final ext = storedPath.split('.').last.toLowerCase();
    final List<Chapter> chapters;
    switch (ext) {
      case 'pdf':
        chapters = await _parsePdf(file);
        break;
      case 'txt':
        chapters = _parseTextLike(await file.readAsString());
        break;
      case 'md':
      case 'markdown':
        chapters = _parseMarkdown(await file.readAsString());
        break;
      case 'epub':
        throw _ReaderError(FileFailure(
          'EPUB aún no soportado en modo offline. '
          'Convierte el libro a PDF o TXT mientras tanto.',
        ));
      default:
        throw _ReaderError(FileFailure(
          'Formato $ext no soportado en modo offline.',
        ));
    }

    if (chapters.isEmpty) {
      throw _ReaderError(FileFailure(
        'No se pudo extraer texto del archivo. ¿Es un PDF escaneado?',
      ));
    }

    // 4) Persistir cache + actualizar metadata del libro.
    _memoryCache[bookId] = chapters;
    await cacheFile.writeAsString(
      jsonEncode(chapters.map(_chapterToJson).toList(growable: false)),
      flush: true,
    );
    await _store.updateBookProgress(
      bookId: bookId,
      totalChapters: chapters.length,
      totalWords: chapters.fold<int>(0, (sum, c) => sum + c.wordCount),
    );
    return chapters;
  }

  String _chaptersCachePathFor(String storedPath) {
    // Para `/path/{id}.pdf` → `/path/{id}.chapters.json`
    final dot = storedPath.lastIndexOf('.');
    final base = dot > 0 ? storedPath.substring(0, dot) : storedPath;
    return '$base.chapters.json';
  }

  // ---------- format parsers ----------

  Future<List<Chapter>> _parsePdf(File file) async {
    // PdfDocument carga todo el PDF en memoria. Para libros muy grandes
    // (>100MB) puede ser costoso, pero la API de syncfusion no soporta
    // streaming, así que es lo que hay.
    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      final pageCount = document.pages.count;
      final pages = <String>[];
      for (var i = 0; i < pageCount; i++) {
        // extractText() en una sola página es estable y rápido.
        final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
        pages.add(pageText);
      }
      final fullText = pages.join('\n\n');
      return _splitByWordCount(fullText);
    } finally {
      document.dispose();
    }
  }

  List<Chapter> _parseMarkdown(String content) {
    // Si hay headers H1/H2, los usamos como cortes naturales.
    final headerPattern = RegExp(r'^(#{1,2})\s+(.+)$', multiLine: true);
    final matches = headerPattern.allMatches(content).toList();
    if (matches.length < 2) {
      // Sin estructura clara: dividimos por tamaño.
      return _splitByWordCount(content);
    }

    final chapters = <Chapter>[];
    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end = (i + 1 < matches.length) ? matches[i + 1].start : content.length;
      final title = matches[i].group(2)?.trim() ?? 'Capítulo ${i + 1}';
      final body = content.substring(start, end).trim();
      final words = _tokenize(body);
      chapters.add(Chapter(
        id: _chapterId(i),
        title: title,
        orderIndex: i,
        wordCount: words.length,
        text: body,
        words: words,
      ));
    }
    return chapters;
  }

  List<Chapter> _parseTextLike(String content) {
    // Intentamos detectar "Capítulo X" / "Chapter X" como cortes.
    final pattern = RegExp(
      r'^\s*(Cap[íi]tulo|Chapter)\s+([IVXLC\d]+)(?:\s*[\.\-:–]\s*(.+))?\s*$',
      multiLine: true,
      caseSensitive: false,
    );
    final matches = pattern.allMatches(content).toList();
    if (matches.length < 2) {
      return _splitByWordCount(content);
    }

    final chapters = <Chapter>[];
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final start = m.start;
      final end = (i + 1 < matches.length) ? matches[i + 1].start : content.length;
      final keyword = m.group(1) ?? 'Capítulo';
      final number = m.group(2) ?? '${i + 1}';
      final subtitle = m.group(3)?.trim();
      final title = subtitle == null || subtitle.isEmpty
          ? '$keyword $number'
          : '$keyword $number — $subtitle';
      final body = content.substring(start, end).trim();
      final words = _tokenize(body);
      chapters.add(Chapter(
        id: _chapterId(i),
        title: title,
        orderIndex: i,
        wordCount: words.length,
        text: body,
        words: words,
      ));
    }
    return chapters;
  }

  /// Divide texto plano en capítulos de aproximadamente
  /// [_targetWordsPerChapter] palabras, cortando en saltos de párrafo
  /// para no partir oraciones por la mitad.
  List<Chapter> _splitByWordCount(String content) {
    final cleaned = content.trim();
    if (cleaned.isEmpty) return const [];

    final paragraphs = cleaned.split(RegExp(r'\n\s*\n'));
    final chapters = <Chapter>[];
    final buffer = StringBuffer();
    var currentWords = 0;
    var idx = 0;

    void flush() {
      final body = buffer.toString().trim();
      if (body.isEmpty) return;
      final words = _tokenize(body);
      chapters.add(Chapter(
        id: _chapterId(idx),
        title: 'Sección ${idx + 1}',
        orderIndex: idx,
        wordCount: words.length,
        text: body,
        words: words,
      ));
      idx++;
      buffer.clear();
      currentWords = 0;
    }

    for (final p in paragraphs) {
      final pTrim = p.trim();
      if (pTrim.isEmpty) continue;
      final wordCount = _tokenize(pTrim).length;
      if (currentWords > 0 && currentWords + wordCount > _targetWordsPerChapter) {
        flush();
      }
      buffer.writeln(pTrim);
      buffer.writeln();
      currentWords += wordCount;
    }
    flush();

    if (chapters.isEmpty) {
      // Documento sin párrafos detectables: lo metemos todo en uno.
      final words = _tokenize(cleaned);
      chapters.add(Chapter(
        id: _chapterId(0),
        title: 'Contenido',
        orderIndex: 0,
        wordCount: words.length,
        text: cleaned,
        words: words,
      ));
    }
    return chapters;
  }

  // ---------- helpers ----------

  String _chapterId(int index) => 'ch-${(index + 1).toString().padLeft(4, '0')}';

  List<String> _tokenize(String content) => content
      .split(RegExp(r'\s+'))
      .map((w) => w.trim())
      .where((w) => w.isNotEmpty)
      .toList(growable: false);

  Map<String, dynamic> _chapterToJson(Chapter c) => {
        'id': c.id,
        'title': c.title,
        'order_index': c.orderIndex,
        'word_count': c.wordCount,
        'text': c.text,
      };

  Chapter _chapterFromJson(Map<String, dynamic> json) {
    final text = json['text'] as String?;
    return Chapter(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Sin título',
      orderIndex: (json['order_index'] as int?) ?? 0,
      wordCount: (json['word_count'] as int?) ?? 0,
      text: text,
      words: text == null ? const [] : _tokenize(text),
    );
  }
}

/// Excepción interna para propagar Failures desde helpers.
class _ReaderError implements Exception {
  _ReaderError(this.failure);
  final Failure failure;
  Failure toFailure() => failure;
}
