import 'dart:io';

/// Nombre común de las cachés de capítulos de un libro offline, que viven
/// junto a su archivo: `/ruta/{id}.pdf` → `/ruta/{id}.chapters.` (más
/// `vN.json`). Lo comparten el lector, que las escribe, y la biblioteca, que
/// las borra con el libro.
String chapterCacheBase(String storedPath) {
  final dot = storedPath.lastIndexOf('.');
  final sep = storedPath.lastIndexOf(Platform.pathSeparator);
  final base = dot > sep + 1 ? storedPath.substring(0, dot) : storedPath;
  return '$base.chapters.';
}

/// Borra las cachés de capítulos del libro de cualquier versión del parser,
/// salvo [keep]. Sin esto, cada subida de versión y cada libro borrado
/// dejaban archivos huérfanos para siempre. Falla en silencio: una caché que
/// sobra solo ocupa sitio.
Future<void> deleteChapterCaches(String storedPath, {String? keep}) async {
  try {
    final base = chapterCacheBase(storedPath);
    final dir = File(storedPath).parent;
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (path == keep) continue;
      if (path.startsWith(base) && path.endsWith('.json')) {
        await entity.delete();
      }
    }
  } catch (_) {
    // Sin permisos o carpeta en uso: se reintentará la próxima vez.
  }
}
