import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/core/utils/sorted_lookup.dart';

void main() {
  group('lastOffsetAtOrBefore', () {
    // Los offsets de párrafo de un capítulo: el párrafo 0 empieza en la
    // palabra 0, el 1 en la 12, etc.
    const offsets = [0, 12, 30, 31, 75];

    test('cae en el tramo que contiene el valor', () {
      expect(lastOffsetAtOrBefore(offsets, 0), 0);
      expect(lastOffsetAtOrBefore(offsets, 11), 0);
      expect(lastOffsetAtOrBefore(offsets, 12), 1);
      expect(lastOffsetAtOrBefore(offsets, 29), 1);
      expect(lastOffsetAtOrBefore(offsets, 200), 4);
    });

    test('con tramos vacíos devuelve el último que empieza ahí', () {
      // El párrafo 2 no tiene palabras (empieza y acaba en la 30), así que
      // la palabra 30 pertenece al 3.
      expect(lastOffsetAtOrBefore(offsets, 30), 2);
      expect(lastOffsetAtOrBefore(offsets, 31), 3);
    });

    test('devuelve -1 si la lista está vacía', () {
      expect(lastOffsetAtOrBefore(const [], 5), -1);
    });

    test('devuelve -1 si el valor es anterior a todo', () {
      expect(lastOffsetAtOrBefore(const [10, 20], 3), -1);
    });

    test('un solo elemento', () {
      expect(lastOffsetAtOrBefore(const [7], 6), -1);
      expect(lastOffsetAtOrBefore(const [7], 7), 0);
      expect(lastOffsetAtOrBefore(const [7], 8), 0);
    });

    test('coincide con la búsqueda lineal en toda una lista larga', () {
      final long = [for (var i = 0; i < 500; i++) i * 3];

      for (var value = -1; value <= 1500; value += 7) {
        var expected = -1;
        for (var i = 0; i < long.length; i++) {
          if (long[i] <= value) expected = i;
        }
        expect(lastOffsetAtOrBefore(long, value), expected,
            reason: 'valor $value');
      }
    });
  });

  group('lastIndexAtOrBefore con clave', () {
    test('busca por el campo indicado', () {
      const marks = [(ms: 0, word: 0), (ms: 250, word: 4), (ms: 900, word: 11)];

      int at(int ms) =>
          lastIndexAtOrBefore(marks, ms, keyOf: (m) => m.ms);

      expect(at(0), 0);
      expect(at(249), 0);
      expect(at(250), 1);
      expect(at(5000), 2);
      expect(at(-1), -1);
    });
  });
}
