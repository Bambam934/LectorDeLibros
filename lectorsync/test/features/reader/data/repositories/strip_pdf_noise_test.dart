import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/local_reader_repository.dart';

/// Casos tomados del libro real "Cálculo Integral" (Fernando Araujo, 2018)
/// extraído en dispositivo el 2026-07-21: el texto llegaba con encabezados
/// de página repetidos (autor / título de sección) con el número pegado, y
/// con el índice completo (relleno de puntos).
void main() {
  group('stripPdfNoise', () {
    test('recorta encabezados/pies repetidos con número de página pegado', () {
      // El mismo prefijo se repite en varias páginas → se detecta y recorta.
      // Se mezclan los dos formatos reales: con espacio tras el número
      // ("RODRÍGUEZ20 Debe") y sin espacio ("INDEFINIDA21Figura").
      final raw = [
        'FERNANDO ARAUJO RODRÍGUEZ20 Debe haber una operación contraria.',
        'INTEGRAL INDEFINIDA21Figura 1 Familia de curvas para varios valores.',
        'FERNANDO ARAUJO RODRÍGUEZ22 Existen dos propiedades muy usadas.',
        'INTEGRAL INDEFINIDA23Ejercicio 3 se deja al estudiante.',
        'FERNANDO ARAUJO RODRÍGUEZ24 Existen propiedades en la solución.',
        'INTEGRAL INDEFINIDA25Capítulo dos técnicas de integración.',
      ].join('\n\n');

      final out = LocalReaderRepository.stripPdfNoise(raw);

      expect(out, isNot(contains('FERNANDO ARAUJO RODRÍGUEZ')));
      expect(out, isNot(contains('INTEGRAL INDEFINIDA')));
      expect(out, contains('Debe haber una operación contraria.'));
      expect(out, contains('Ejercicio 3 se deja al estudiante.'));
    });

    test('elimina los párrafos de índice (relleno de puntos)', () {
      final raw = [
        'Índice de Tablas ............................................. 7',
        'Contenido normal del primer capítulo del libro.',
      ].join('\n\n');

      final out = LocalReaderRepository.stripPdfNoise(raw);

      expect(out, isNot(contains('Índice de Tablas')));
      expect(out, contains('Contenido normal del primer capítulo'));
    });

    test('NO recorta un encabezado que aparece una sola vez', () {
      // "RESUMEN" en mayúsculas + número, pero una sola vez: no es un
      // encabezado de página repetido, así que se conserva íntegro.
      final raw = 'RESUMEN2 del experimento con resultados finales.\n\n'
          'Otro párrafo cualquiera del texto del documento.';

      final out = LocalReaderRepository.stripPdfNoise(raw);

      expect(out, contains('RESUMEN2 del experimento'));
    });

    test('deja intacto un texto sin ruido de PDF', () {
      const raw = 'Primer párrafo normal.\n\nSegundo párrafo normal.';
      expect(LocalReaderRepository.stripPdfNoise(raw), raw);
    });

    test('NO borra los rótulos numerados aunque se repitan', () {
      // Regresión (2026-10-02): la clase perezosa del prefijo incluía el
      // espacio, así que "EJEMPLO 3" casaba con el prefijo "EJEMPLO " y, en
      // cuanto aparecía tres veces, el rótulo desaparecía de todos los
      // párrafos. En un libro de cálculo eso borra cada "EJEMPLO n",
      // "TEOREMA n" y "CAPÍTULO n" del texto que se lee.
      final raw = [
        'EJEMPLO 1 Calcule la integral de x.',
        'EJEMPLO 2 Calcule la derivada de x al cuadrado.',
        'EJEMPLO 3 Halle el área bajo la curva.',
        'CAPÍTULO 1 La derivada mide el cambio.',
        'CAPÍTULO 2 La integral acumula.',
        'CAPÍTULO 3 El límite se aproxima.',
      ].join('\n\n');

      final out = LocalReaderRepository.stripPdfNoise(raw);

      expect(out, raw);
    });

    test('sigue recortando el encabezado con el número pegado', () {
      // La otra cara del arreglo: lo que SÍ es ruido de página se quita.
      final raw = [
        'CÁLCULO INTEGRAL10 Primera página del capítulo.',
        'CÁLCULO INTEGRAL11 Segunda página.',
        'CÁLCULO INTEGRAL12 Tercera página.',
      ].join('\n\n');

      final out = LocalReaderRepository.stripPdfNoise(raw);

      expect(out, isNot(contains('CÁLCULO INTEGRAL')));
      expect(out, contains('Primera página del capítulo.'));
    });
  });
}
