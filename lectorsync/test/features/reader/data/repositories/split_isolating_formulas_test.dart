import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/tts/speak_segment.dart';
import 'package:lectorsync/features/reader/data/repositories/tts/tts_segmentation.dart';

/// Tests de la tubería COMPLETA: segmentación real + silenciado.
///
/// Los tests de `muteFormulaSegments` la alimentan con `SpeakSegment` hechos
/// a mano que contienen una fórmula aislada — exactamente la condición que la
/// tubería real nunca producía. Por eso el silenciado pasaba su suite entera
/// sin funcionar en la app: `looksLikeFormula` mide proporciones del bloque
/// entero, y los bloques reales (200 palabras, u oraciones fusionadas con la
/// prosa vecina) diluyen esas proporciones muy por encima del umbral.
///
/// Aquí se parte del texto de un capítulo, como en producción.

const _formula = '10.50.5(1)2+1=';

/// Prosa determinista: [n] palabras reales, sin símbolos matemáticos.
String _prose(int n, {String seed = 'palabra'}) =>
    List.generate(n, (i) => '$seed${i % 7}').join(' ');

List<String> _tokenize(String text) =>
    text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

void main() {
  group('splitIsolatingFormulas + muteFormulaSegments', () {
    test('silencia la fórmula de un capítulo real en Android/iOS', () {
      // `splitIntoSegments` (la rama con word-boundary) trocea de 200 en 200
      // palabras: sin aislar antes el párrafo, la fórmula viajaba dentro de
      // un bloque de prosa y nunca se detectaba.
      final text = '${_prose(150)}\n\n$_formula\n\n${_prose(150)}';
      final words = _tokenize(text);

      final segments = muteFormulaSegments(
        splitIsolatingFormulas(text, words, 0, segmentProse: splitIntoSegments),
      );

      final muted = segments.where((s) => s.isFormula).toList();
      expect(muted, hasLength(1));
      expect(muted.single.text, kFormulaSpokenReplacement);
      expect(
        segments.any((s) => s.text.contains(_formula)),
        isFalse,
        reason: 'la ecuación aplanada no debe quedar en ningún segmento',
      );
    });

    test('silencia la fórmula también en escritorio/web', () {
      // `splitIntoSentences` corta en `.!?;` seguidos de espacio. Una fórmula
      // termina en `=` y sus puntos internos van seguidos de dígito, así que
      // sin aislarla quedaba pegada a la frase siguiente.
      final text = 'Sea f una función continua.\n\n'
          '$_formula\n\n'
          'Donde F es una primitiva de f.';
      final words = _tokenize(text);

      final segments = muteFormulaSegments(
        splitIsolatingFormulas(text, words, 0, segmentProse: splitIntoSentences),
      );

      expect(segments.where((s) => s.isFormula), hasLength(1));
      expect(segments.any((s) => s.text.contains(_formula)), isFalse);
    });

    test('no toca la prosa que rodea a la fórmula', () {
      final text = 'Sea f una función continua en el intervalo.\n\n'
          '$_formula\n\n'
          'Donde F es una primitiva de f.';
      final words = _tokenize(text);

      final segments = muteFormulaSegments(
        splitIsolatingFormulas(text, words, 0, segmentProse: splitIntoSentences),
      );

      final spoken = segments.map((s) => s.text).join(' ');
      expect(spoken, contains('función continua'));
      expect(spoken, contains('primitiva'));
    });

    test('conserva la alineación del seguidor de palabras', () {
      // Lo esencial: las palabras de todos los segmentos, concatenadas, son
      // la lista original, y cada segmento declara dónde empieza.
      final text = '${_prose(40)}\n\n$_formula\n\n${_prose(40)}';
      final words = _tokenize(text);

      final segments = muteFormulaSegments(
        splitIsolatingFormulas(text, words, 0, segmentProse: splitIntoSegments),
      );

      expect(segments.expand((s) => s.words).toList(), words);

      var expectedStart = 0;
      for (final s in segments) {
        expect(s.globalStartWordIndex, expectedStart);
        expectedStart += s.words.length;
      }
      expect(expectedStart, words.length);
    });

    test('respeta un arranque a media lectura', () {
      final text = '$_formula\n\n${_prose(20)}';
      final words = _tokenize(text);

      final segments = splitIsolatingFormulas(
        text,
        words,
        137,
        segmentProse: splitIntoSegments,
      );

      expect(segments.first.globalStartWordIndex, 137);
      expect(
        segments.last.globalStartWordIndex + segments.last.words.length,
        137 + words.length,
      );
    });

    test('sin fórmulas devuelve exactamente la segmentación de siempre', () {
      // El caso común no debe cambiar de comportamiento: mismos cortes,
      // mismos textos, mismos índices.
      final text = '${_prose(120)}\n\n${_prose(120, seed: 'otra')}';
      final words = _tokenize(text);

      final viaIsolating =
          splitIsolatingFormulas(text, words, 0, segmentProse: splitIntoSegments);
      final direct = splitIntoSegments(text, words, 0);

      expect(viaIsolating.map((s) => s.text), direct.map((s) => s.text));
      expect(
        viaIsolating.map((s) => s.globalStartWordIndex),
        direct.map((s) => s.globalStartWordIndex),
      );
    });

    test('aísla varias fórmulas del mismo capítulo', () {
      final text = '${_prose(30)}\n\n'
          '$_formula\n\n'
          '${_prose(30)}\n\n'
          'x = 5\n\n'
          '${_prose(30)}';
      final words = _tokenize(text);

      final segments = muteFormulaSegments(
        splitIsolatingFormulas(text, words, 0, segmentProse: splitIntoSegments),
      );

      expect(segments.where((s) => s.isFormula), hasLength(2));
      expect(segments.expand((s) => s.words).toList(), words);
    });

    test('un texto sin párrafos se segmenta como siempre', () {
      final text = _prose(50);
      final words = _tokenize(text);

      expect(
        splitIsolatingFormulas(text, words, 0, segmentProse: splitIntoSegments)
            .map((s) => s.text),
        splitIntoSegments(text, words, 0).map((s) => s.text),
      );
    });

    test('una lista de palabras vacía no produce segmentos', () {
      expect(
        splitIsolatingFormulas('', const [], 0,
            segmentProse: splitIntoSegments),
        isEmpty,
      );
    });

    test('marca isFormula solo en los segmentos silenciados', () {
      final text = '${_prose(30)}\n\n$_formula';
      final words = _tokenize(text);

      final segments = muteFormulaSegments(
        splitIsolatingFormulas(text, words, 0, segmentProse: splitIntoSegments),
      );

      final prose = segments.where((s) => !s.isFormula);
      expect(prose, isNotEmpty);
      for (final s in prose) {
        expect(s.text, isNot(kFormulaSpokenReplacement));
      }
    });
  });

  group('SpeakSegment.isFormula', () {
    test('por defecto es falso', () {
      const s = SpeakSegment(
        text: 'Hola.',
        words: ['Hola.'],
        globalStartWordIndex: 0,
        audibleCharCount: 5,
        hasNumbers: false,
      );

      expect(s.isFormula, isFalse);
    });
  });
}
