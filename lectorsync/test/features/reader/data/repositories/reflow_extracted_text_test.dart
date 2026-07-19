import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/local_reader_repository.dart';

/// Casos tomados de la lectura real en dispositivo (2026-07-19): el texto
/// extraído del PDF llegaba con los saltos de línea de la maquetación, lo
/// que producía párrafos huérfanos de una palabra ("Su", "En") y frases
/// partidas a media línea.
void main() {
  group('reflowExtractedText', () {
    test('une los saltos de maquetación dentro de un párrafo', () {
      const raw = 'El romanticismo, que promueve la variedad, encaja bien\n'
          'con el consumismo.\n'
          'Su\n'
          'matrimonio ha dado origen al infinito «mercado de experiencias»\n'
          'sobre el que se cimienta la moderna industria del turismo.';

      final result = LocalReaderRepository.reflowExtractedText(raw);

      expect(result, isNot(contains('\n')));
      expect(result, contains('encaja bien con el consumismo. Su matrimonio'));
    });

    test('la línea en blanco sí separa párrafos', () {
      const raw = 'Primera frase del párrafo uno\n'
          'que continuaba abajo.\n'
          '\n'
          'Segundo párrafo que también\n'
          'venía cortado.';

      final result = LocalReaderRepository.reflowExtractedText(raw);
      final paragraphs = result.split('\n\n');

      expect(paragraphs, hasLength(2));
      expect(paragraphs[0], 'Primera frase del párrafo uno que continuaba abajo.');
      expect(paragraphs[1], 'Segundo párrafo que también venía cortado.');
    });

    test('reconstruye palabras partidas por guion al final de línea', () {
      const raw = 'Los mitos del consu-\nmismo son poderosos.';

      final result = LocalReaderRepository.reflowExtractedText(raw);

      expect(result, 'Los mitos del consumismo son poderosos.');
    });

    test('no altera el número de palabras', () {
      const raw = 'Una frase\ncortada en varias\nlíneas distintas.\n\n'
          'Otro párrafo\naquí.';

      int countWords(String s) =>
          s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

      final result = LocalReaderRepository.reflowExtractedText(raw);

      expect(countWords(result), countWords(raw));
    });

    test('normaliza saltos de Windows y descarta líneas vacías sobrantes', () {
      const raw = 'Primera línea\r\nsegunda línea\r\n\r\n\r\nOtro párrafo';

      final result = LocalReaderRepository.reflowExtractedText(raw);

      expect(result, 'Primera línea segunda línea\n\nOtro párrafo');
    });

    test('texto vacío o solo espacios devuelve cadena vacía', () {
      expect(LocalReaderRepository.reflowExtractedText(''), '');
      expect(LocalReaderRepository.reflowExtractedText('   \n\n  \n'), '');
    });
  });
}
