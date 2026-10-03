import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/tts/speak_segment.dart';
import 'package:lectorsync/features/reader/data/repositories/tts/tts_segmentation.dart';

SpeakSegment _seg(String text, {int start = 0}) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  return SpeakSegment(
    text: text,
    words: words,
    globalStartWordIndex: start,
    audibleCharCount: computeAudibleCharCount(text),
    hasNumbers: detectNumbers(text),
  );
}

void main() {
  group('muteFormulaSegments', () {
    test('sustituye el texto de la fórmula por el aviso hablado', () {
      final result = muteFormulaSegments([_seg('10.50.5(1)2+1=')]);

      expect(result.single.text, kFormulaSpokenReplacement);
    });

    test('no toca la prosa', () {
      const prose = 'La regla de Barrow relaciona derivada e integral.';
      final result = muteFormulaSegments([_seg(prose)]);

      expect(result.single.text, prose);
    });

    test('conserva la alineación del seguidor de palabras', () {
      // Lo esencial: el motor dice menos, pero el índice global sigue
      // cayendo donde caería si hubiera leído la ecuación entera.
      final original = _seg('∫ f(x) dx = F(b) − F(a)', start: 120);
      final muted = muteFormulaSegments([original]).single;

      expect(muted.words, original.words);
      expect(muted.globalStartWordIndex, 120);
    });

    test('recalcula la duración estimada sobre el texto nuevo', () {
      final original = _seg('∑ i=1 n (2i + 1) = n²');
      final muted = muteFormulaSegments([original]).single;

      expect(muted.audibleCharCount,
          computeAudibleCharCount(kFormulaSpokenReplacement));
      expect(muted.audibleCharCount, lessThan(original.audibleCharCount));
    });

    test('marca el segmento como libre de números', () {
      // El texto sustituido no tiene cifras, y dejar hasNumbers en true
      // sesgaría la calibración de ms/char del tracker.
      final muted = muteFormulaSegments([_seg('x = 5')]).single;

      expect(muted.hasNumbers, isFalse);
    });

    test('respeta el orden y silencia solo lo que toca', () {
      final segments = [
        _seg('Sea f una función continua.', start: 0),
        _seg('∫ f(x) dx = F(b) − F(a)', start: 5),
        _seg('Donde F es una primitiva de f.', start: 13),
      ];

      final result = muteFormulaSegments(segments);

      expect(result.length, 3);
      expect(result[0].text, segments[0].text);
      expect(result[1].text, kFormulaSpokenReplacement);
      expect(result[2].text, segments[2].text);
      expect(result.map((s) => s.globalStartWordIndex), [0, 5, 13]);
    });

    test('devuelve la misma lista si no hay ninguna fórmula', () {
      final segments = [_seg('Primero.'), _seg('Segundo.')];

      expect(identical(muteFormulaSegments(segments), segments), isTrue);
    });

    test('acepta una lista vacía', () {
      expect(muteFormulaSegments(const []), isEmpty);
    });

    test('admite un reemplazo a medida', () {
      final result = muteFormulaSegments(
        [_seg('x = 5')],
        replacement: 'Ecuación.',
      );

      expect(result.single.text, 'Ecuación.');
    });
  });
}
