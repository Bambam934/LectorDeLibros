import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/core/constants/import_limits.dart';
import 'package:lectorsync/features/library/presentation/utils/picked_book_reader.dart';

void main() {
  group('readPickedBook', () {
    const customLimit = 100;

    test(
        'CA-1: devuelve demasiado grande y no se suscribe al stream cuando size > maxBytes',
        () async {
      var subscribed = false;
      final controller = StreamController<List<int>>.broadcast(
        onListen: () {
          subscribed = true;
          fail('No debía suscribirse a readStream cuando size > maxBytes');
        },
      );

      final file = PlatformFile(
        name: 'demasiado_grande.epub',
        size: customLimit + 1,
        readStream: controller.stream,
      );

      final result = await readPickedBook(file, maxBytes: customLimit);

      expect(result, isA<PickedBookTooLarge>());
      expect(subscribed, isFalse);
      unawaited(controller.close());
    });

    test('CA-1 con límite por defecto (kMaxImportBytes): no se suscribe si supera el tope',
        () async {
      var subscribed = false;
      final controller = StreamController<List<int>>.broadcast(
        onListen: () {
          subscribed = true;
          fail('No debía suscribirse a readStream al superar kMaxImportBytes');
        },
      );

      final file = PlatformFile(
        name: 'libro_enorme.pdf',
        size: kMaxImportBytes + 1,
        readStream: controller.stream,
      );

      final result = await readPickedBook(file);

      expect(result, isA<PickedBookTooLarge>());
      expect(subscribed, isFalse);
      unawaited(controller.close());
    });

    test('CA-2: con size <= maxBytes y un readStream de 3 trozos devuelve los bytes concatenados exactos',
        () async {
      final chunk1 = [1, 2, 3];
      final chunk2 = [4, 5, 6, 7];
      final chunk3 = [8, 9, 10];
      final expected = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

      final file = PlatformFile(
        name: 'libro.pdf',
        size: expected.length,
        readStream: Stream.fromIterable([chunk1, chunk2, chunk3]),
      );

      final result = await readPickedBook(file, maxBytes: customLimit);

      expect(result, isA<PickedBookBytes>());
      expect((result as PickedBookBytes).bytes, equals(expected));
    });

    test('CA-3: sin readStream y con bytes devuelve esos bytes', () async {
      final expected = Uint8List.fromList([65, 66, 67, 68]);

      final file = PlatformFile(
        name: 'libro.txt',
        size: expected.length,
        bytes: expected,
      );

      final result = await readPickedBook(file, maxBytes: customLimit);

      expect(result, isA<PickedBookBytes>());
      expect((result as PickedBookBytes).bytes, equals(expected));
    });

    test('CA-3: sin readStream ni bytes devuelve ilegible', () async {
      final file = PlatformFile(
        name: 'inaccesible.epub',
        size: 50,
      );

      final result = await readPickedBook(file, maxBytes: customLimit);

      expect(result, isA<PickedBookUnreadable>());
    });

    test('devuelve ilegible si el stream emite un error durante la lectura',
        () async {
      final controller = StreamController<List<int>>();
      controller.addError(Exception('Fallo de I/O'));

      final file = PlatformFile(
        name: 'fallo.pdf',
        size: 10,
        readStream: controller.stream,
      );

      final result = await readPickedBook(file, maxBytes: customLimit);

      expect(result, isA<PickedBookUnreadable>());
      await controller.close();
    });
  });
}
