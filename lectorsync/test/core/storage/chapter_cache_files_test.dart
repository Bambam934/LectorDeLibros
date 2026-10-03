import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/core/storage/chapter_cache_files.dart';

void main() {
  late Directory dir;
  late String stored;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lectorsync_cache_');
    stored = '${dir.path}${Platform.pathSeparator}libro.pdf';
    for (final name in [
      'libro.pdf',
      'libro.chapters.json',
      'libro.chapters.v3.json',
      'libro.chapters.v4.json',
      'otro.chapters.v4.json',
      'libro.notas.json',
    ]) {
      await File('${dir.path}${Platform.pathSeparator}$name').writeAsString('x');
    }
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Set<String> names() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toSet();

  test('al reprocesar, borra las versiones viejas y conserva la actual',
      () async {
    await deleteChapterCaches(stored, keep: '${chapterCacheBase(stored)}v4.json');

    expect(names(), {
      'libro.pdf',
      'libro.chapters.v4.json',
      'otro.chapters.v4.json',
      'libro.notas.json',
    });
  });

  test('al borrar el libro, borra todas sus cachés y nada más', () async {
    await deleteChapterCaches(stored);

    expect(names(), {'libro.pdf', 'otro.chapters.v4.json', 'libro.notas.json'});
  });

  test('un punto en la carpeta no se toma por la extensión', () {
    final sep = Platform.pathSeparator;
    expect(
      chapterCacheBase('${sep}datos.v2${sep}libro'),
      '${sep}datos.v2${sep}libro.chapters.',
    );
  });
}
