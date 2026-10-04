import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/parsing/formula_detector.dart';

void main() {
  group('looksLikeFormula — reconoce fórmulas', () {
    test('la tira aplanada que reportó el usuario', () {
      // Tal cual salió del PDF de ecuaciones integrales.
      expect(looksLikeFormula('10.50.5(1)2+1='), isTrue);
    });

    test('una ecuación con notación matemática', () {
      expect(looksLikeFormula('∫ f(x) dx = F(b) − F(a)'), isTrue);
    });

    test('una asignación corta', () {
      expect(looksLikeFormula('x = 5'), isTrue);
    });

    test('un sumatorio con índices', () {
      expect(looksLikeFormula('∑ i=1 n (2i + 1) = n²'), isTrue);
    });

    test('una expresión con fracción y raíz', () {
      expect(looksLikeFormula('(-b ± √(b^2-4ac)) / 2a'), isTrue);
    });
  });

  group('looksLikeFormula — no confunde la prosa', () {
    test('una frase con cifras', () {
      expect(
        looksLikeFormula('El capítulo 3 trata de la integral definida entre 0 y 1.'),
        isFalse,
      );
    });

    test('una referencia a una ecuación', () {
      expect(looksLikeFormula('Ver ecuación (2.14).'), isFalse);
    });

    test('un título numerado', () {
      expect(looksLikeFormula('1. Introducción'), isFalse);
    });

    test('un número de página suelto', () {
      expect(looksLikeFormula('42'), isFalse);
    });

    test('una numeración romana', () {
      expect(looksLikeFormula('III'), isFalse);
    });

    test('una cadena vacía o solo espacios', () {
      expect(looksLikeFormula(''), isFalse);
      expect(looksLikeFormula('   \n  '), isFalse);
    });

    test('prosa que menciona variables', () {
      expect(
        looksLikeFormula(
          'Despejamos x en la ecuación anterior y sustituimos su valor.',
        ),
        isFalse,
      );
    });

    test('una lista de fechas', () {
      expect(looksLikeFormula('Madrid, 12 de octubre de 1492'), isFalse);
    });

    test('los teléfonos y faxes de una página de créditos', () {
      // De "Cálculo integral": salían enmarcados como fórmula.
      expect(looksLikeFormula('P.B.X. (+593 7) 2050000'), isFalse);
      expect(looksLikeFormula('Fax: (+593 7) 4 088958'), isFalse);
      expect(looksLikeFormula('(+593 7) 2050000'), isFalse);
      expect(looksLikeFormula('Tel. 2050000'), isFalse);
    });
  });

  group('sobre un capítulo entero', () {
    // Es como lo usan los dos consumidores reales: la UI mapea los párrafos
    // del capítulo y el TTS los aísla antes de segmentar.
    test('señala solo los párrafos que son fórmula', () {
      final paragraphs = [
        'La regla de Barrow relaciona la derivada con la integral.',
        '∫ f(x) dx = F(b) − F(a)',
        'Donde F es una primitiva cualquiera de f.',
        '10.50.5(1)2+1=',
      ];

      expect(paragraphs.map(looksLikeFormula), [false, true, false, true]);
    });

    test('no marca nada en un texto sin fórmulas', () {
      expect(
        ['Primer párrafo.', 'Segundo párrafo.'].any(looksLikeFormula),
        isFalse,
      );
    });
  });
}
