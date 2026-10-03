import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/presentation/reading_typography.dart';
import 'package:lectorsync/features/settings/domain/entities/reading_preferences.dart';
import 'package:flutter/material.dart' show TextAlign;

void main() {
  group('paragraphIndent', () {
    test('escala con el tamaño del cuerpo', () {
      // El punto de hacerla proporcional: 24 px fijos se notaban a 14 px de
      // cuerpo y desaparecían a 32.
      expect(paragraphIndent(fontSize: 14), 14 * indentEm);
      expect(paragraphIndent(fontSize: 32), 32 * indentEm);
      expect(
        paragraphIndent(fontSize: 32),
        greaterThan(paragraphIndent(fontSize: 14)),
      );
    });

    test('el primer párrafo del capítulo no se sangra', () {
      expect(paragraphIndent(fontSize: 18, isFirstParagraph: true), 0);
    });

    test('una fórmula no se sangra', () {
      expect(paragraphIndent(fontSize: 18, isFormula: true), 0);
    });

    test('el resto de párrafos sí se sangran', () {
      expect(paragraphIndent(fontSize: 18), greaterThan(0));
    });
  });

  group('jerarquía del encabezado de capítulo', () {
    test('el título siempre es mayor que el cuerpo', () {
      // La regresión que arregla: con tamaños fijos (28/20), subir el cuerpo
      // a 32 dejaba el título más pequeño que el texto que encabeza.
      for (final body in [14.0, 18.0, 24.0, 32.0]) {
        expect(
          chapterTitleSize(body),
          greaterThan(body),
          reason: 'cuerpo de $body px',
        );
      }
    });

    test('el número de capítulo es mayor que el título', () {
      for (final body in [14.0, 18.0, 24.0, 32.0]) {
        expect(chapterNumberSize(body), greaterThan(chapterTitleSize(body)));
      }
    });
  });

  group('medida de línea', () {
    test('una columna de móvil se queda corta para justificar', () {
      // ~360 px de ancho útil con cuerpo de 18 px: por debajo del rango
      // cómodo, que es justo donde el justificado abre huecos.
      final chars = charactersPerLine(width: 360, fontSize: 18);

      expect(chars, lessThan(minComfortableMeasure));
      expect(isComfortableMeasure(width: 360, fontSize: 18), isFalse);
    });

    test('la columna por defecto da la medida clásica', () {
      const prefs = ReadingPreferences();
      final chars = charactersPerLine(
        width: prefs.maxColumnWidth,
        fontSize: prefs.fontSize,
      );

      expect(chars, closeTo(66, 3), reason: 'la medida clásica son 66');
      expect(isComfortableMeasure(width: 600, fontSize: 18), isTrue);
    });

    test('720 px ya se pasa de ancho', () {
      // Era el valor por defecto anterior: ~80 caracteres por línea, por
      // encima del rango. Sigue disponible en el panel para quien lo quiera.
      expect(isComfortableMeasure(width: 720, fontSize: 18), isFalse);
    });

    test('una columna sin límite se pasa de ancha', () {
      expect(isComfortableMeasure(width: 1400, fontSize: 18), isFalse);
    });

    test('no divide por cero con un tamaño inválido', () {
      expect(charactersPerLine(width: 720, fontSize: 0), 0);
    });
  });

  group('ReadingPreferences.textAlign', () {
    test('por defecto no justifica', () {
      // Flutter no parte palabras: justificar sin guionado deja ríos de
      // blanco en la columna estrecha de un móvil.
      expect(const ReadingPreferences().justifyText, isFalse);
      expect(const ReadingPreferences().textAlign, TextAlign.left);
    });

    test('respeta a quien sí lo quiere', () {
      const prefs = ReadingPreferences(justifyText: true);
      expect(prefs.textAlign, TextAlign.justify);
    });
  });
}
