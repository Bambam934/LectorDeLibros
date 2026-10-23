import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/core/errors/failures.dart';
import 'package:lectorsync/features/library/data/repositories/local_library_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('LocalLibraryRepository.importBook — tope de tamaño', () {
    const limit = LocalLibraryRepository.maxImportBytes;

    test('el tope es el mismo que el del backend: 50 MiB', () {
      expect(limit, 50 * 1024 * 1024);
    });

    test('rechaza un archivo de más de 50 MiB sin tocar el disco ni el catálogo',
        () async {
      final repo = LocalLibraryRepository();

      final result = await repo.importBook(
        filename: 'grande.pdf',
        bytes: Uint8List(limit + 1),
      );

      final failure = result.getLeft().toNullable();
      expect(failure, isA<FileFailure>());
      expect(failure!.message, contains('50 MB'));
      // Ni path_provider (que en los tests lanzaría) ni SharedPreferences:
      // el catálogo sigue vacío.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('un archivo de 50 MiB exactos no se rechaza por tamaño', () async {
      final repo = LocalLibraryRepository();

      final result = await repo.importBook(
        filename: 'justo.pdf',
        bytes: Uint8List(limit),
      );

      // Sin plataforma, el guardado falla más adelante (path_provider); lo
      // que importa es que no sea el fallo del límite.
      final failure = result.getLeft().toNullable();
      expect(failure?.message ?? '', isNot(contains('50 MB')));
    });
  });
}
