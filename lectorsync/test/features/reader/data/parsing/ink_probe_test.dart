import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/parsing/ink_probe.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter_block.dart';

/// Imagen BGRA blanca de [w] × [h] con píxeles negros donde diga [ink].
Uint8List _image(int w, int h, bool Function(int x, int y) ink) {
  final pixels = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!ink(x, y)) continue;
      final o = (y * w + x) * 4;
      pixels[o] = pixels[o + 1] = pixels[o + 2] = 0;
    }
  }
  return pixels;
}

PageRect? _scan(Uint8List pixels) =>
    PdfrxInkProbe.scanInk(pixels, 100, 100, const PageRect(0, 0, 100, 100), 1);

void main() {
  group('PdfrxInkProbe.scanInk', () {
    test('una página en blanco no tiene tinta', () {
      expect(_scan(_image(100, 100, (_, _) => false)), isNull);
    });

    test('una foto oscura, con casi todas las filas llenas, es una imagen', () {
      final bounds =
          _scan(_image(100, 100, (x, y) => x >= 20 && x < 80 && y >= 20 && y < 80));

      expect(bounds, const PageRect(20, 20, 80, 80));
    });

    test('el borde de un recuadro sin nada dentro no es una imagen', () {
      final frame = _image(100, 100, (x, y) {
        final inBox = x >= 20 && x < 80 && y >= 20 && y < 80;
        final border = x == 20 || x == 79 || y == 20 || y == 21 || y == 78 || y == 79;
        return inBox && border;
      });

      expect(_scan(frame), isNull);
    });

    test('una fórmula dentro del hueco cuenta', () {
      final bounds =
          _scan(_image(100, 100, (x, y) => x % 3 == 0 && y >= 40 && y < 60));

      expect(bounds, isNotNull);
    });
  });
}
