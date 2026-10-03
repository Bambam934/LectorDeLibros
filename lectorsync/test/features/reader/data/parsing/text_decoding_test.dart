import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/parsing/text_decoding.dart';

void main() {
  group('decodeTextBytes', () {
    test('UTF-8 queda igual', () {
      const text = 'Capítulo 1\n\n¿Qué pasó? Ñandú, pingüino.';
      expect(decodeTextBytes(Uint8List.fromList(utf8.encode(text))), text);
    });

    test('quita el BOM de UTF-8', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('Hola')]);
      expect(decodeTextBytes(bytes), 'Hola');
    });

    test('un TXT "ANSI" de Windows se lee con sus tildes y su tipografía', () {
      // "Canción: “ñandú” — fin…" en Windows-1252.
      final bytes = Uint8List.fromList([
        0x43, 0x61, 0x6E, 0x63, 0x69, 0xF3, 0x6E, 0x3A, 0x20, // Canción:
        0x93, 0xF1, 0x61, 0x6E, 0x64, 0xFA, 0x94, 0x20, // “ñandú”
        0x97, 0x20, 0x66, 0x69, 0x6E, 0x85, // — fin…
      ]);
      expect(decodeTextBytes(bytes), 'Canción: “ñandú” — fin…');
    });

    test('los huecos sin asignar de Windows-1252 no rompen la lectura', () {
      final bytes = Uint8List.fromList([0x41, 0x81, 0xE9]);
      expect(decodeTextBytes(bytes), 'A\u0081é');
    });
  });
}
