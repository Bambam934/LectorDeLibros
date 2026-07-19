/// Contrato del almacenamiento local de libros que el lector offline
/// necesita: resolver la ruta del archivo persistido en el dispositivo y
/// actualizar la metadata del catálogo (capítulos, palabras, progreso).
///
/// Vive en `core/` a propósito: así el feature `reader` no depende de la
/// capa `data` del feature `library`. Lo implementa `LocalLibraryRepository`,
/// que en modo offline es la misma instancia expuesta también como
/// `LibraryRepository`.
abstract interface class LocalBookStore {
  /// Ruta absoluta del archivo de un libro en el dispositivo, o `null` si
  /// no existe en el catálogo local.
  Future<String?> resolveStoredPath(String bookId);

  /// Actualiza progreso y/o metadata (capítulos, palabras) del libro en el
  /// catálogo local. Los parámetros nulos dejan el valor previo intacto.
  Future<void> updateBookProgress({
    required String bookId,
    int? totalChapters,
    int? totalWords,
    double? progress,
    String? progressChapterId,
    int? progressWordIndex,
  });
}
