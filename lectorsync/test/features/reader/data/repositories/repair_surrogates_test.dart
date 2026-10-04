import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/local_reader_repository.dart';

/// Caso real (2026-10-03, Windows): Syncfusion extraía la 𝑥 cursiva de las
/// fórmulas (U+1D465, `D835 DC65`) como `D835 0C65`, y Flutter lanzaba
/// «string is not well-formed UTF-16» al pintar el párrafo.
void main() {
  group('repairSurrogates', () {
    test('recompone el par con la segunda mitad mutilada', () {
      final broken = String.fromCharCodes([0x32, 0x20, 0xD835, 0x0C65, 0x20, 0x3D]);

      expect(LocalReaderRepository.repairSurrogates(broken), '2 𝑥 =');
    });

    test('cambia por U+FFFD las mitades que no se pueden recomponer', () {
      final broken = String.fromCharCodes([0x61, 0xD835, 0x62, 0xDC65, 0x63]);

      expect(LocalReaderRepository.repairSurrogates(broken), 'a�b�c');
    });

    test('un sustituto alto al final del texto también se sustituye', () {
      final broken = String.fromCharCodes([0x61, 0xD835]);

      expect(LocalReaderRepository.repairSurrogates(broken), 'a�');
    });

    test('deja intacto el texto bien formado, incluidos los pares válidos', () {
      const ok = 'Sea 𝑥 ≤ 20 y 𝑦 = 3 😀 ñandú';

      expect(identical(LocalReaderRepository.repairSurrogates(ok), ok), isTrue);
    });
  });
}
