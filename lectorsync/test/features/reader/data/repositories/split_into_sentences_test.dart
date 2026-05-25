import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/device_tts_repository.dart';

/// Tests for FIX 78 (session 16) — sentence-aligned segmentation that
/// eliminates the mid-segment drift caused by the TTS engine pausing
/// at punctuation while the timer-based tracker keeps running.
void main() {
  group('splitIntoSentences', () {
    List<String> wordsOf(String s) =>
        s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    test('single sentence returns a single segment', () {
      const text = 'Este es un ejemplo simple sin puntos.';
      final words = wordsOf(text);
      final segs = DeviceTtsRepository.splitIntoSentences(text, words, 0);
      expect(segs, hasLength(1));
      expect(segs.first.words, equals(words));
      expect(segs.first.globalStartWordIndex, 0);
    });

    test('splits on period followed by space', () {
      const text = 'Primera oración. Segunda oración aquí.';
      final words = wordsOf(text);
      final segs = DeviceTtsRepository.splitIntoSentences(text, words, 0);
      // Both sentences are < minMergeChars(30), so they may merge.
      // With default minMergeChars=30 "Primera oración." (16 chars) is
      // shorter than 30 — it should merge with the next.
      expect(segs, hasLength(1));
      expect(segs.first.words.length, words.length);
    });

    test('does NOT merge when both segments meet minimum size', () {
      const text =
          'Esta es una oración bastante larga que supera el umbral mínimo. '
          'Y esta segunda oración también es suficientemente extensa para '
          'mantenerse separada del primer segmento.';
      final words = wordsOf(text);
      final segs = DeviceTtsRepository.splitIntoSentences(text, words, 0);
      expect(segs.length, 2);
      // Boundaries preserve contiguous word coverage.
      final totalWordsInSegs =
          segs.fold<int>(0, (sum, s) => sum + s.words.length);
      expect(totalWordsInSegs, words.length);
      // globalStartWordIndex of second segment equals start + size of first.
      expect(
        segs[1].globalStartWordIndex,
        segs[0].globalStartWordIndex + segs[0].words.length,
      );
    });

    test('splits on question mark and exclamation mark', () {
      const text =
          '¿Qué hora es ahora mismo en esta ciudad tan lejana? ¡Vaya pregunta! '
          'Pero realmente quiero saberlo con precisión absoluta para mi viaje.';
      final words = wordsOf(text);
      final segs = DeviceTtsRepository.splitIntoSentences(text, words, 0);
      // Three sentences, all >= 30 chars (the ?/! ones merged with the
      // following long sentence depending on length).
      expect(segs.length, greaterThanOrEqualTo(2));
      final coverage = segs.fold<int>(0, (sum, s) => sum + s.words.length);
      expect(coverage, words.length);
    });

    test('splits on semicolon', () {
      const text =
          'Esta primera cláusula es una idea completa que termina aquí; '
          'la segunda cláusula expresa otra idea relacionada con la anterior.';
      final words = wordsOf(text);
      final segs = DeviceTtsRepository.splitIntoSentences(text, words, 0);
      expect(segs.length, 2);
    });

    test('does NOT split on comma (kept inside same segment)', () {
      const text =
          'Aquí hay una lista, con varias comas, que mantiene todo en una sola '
          'oración, sin importar cuántas pausas pequeñas haya en el medio.';
      final words = wordsOf(text);
      final segs = DeviceTtsRepository.splitIntoSentences(text, words, 0);
      expect(segs, hasLength(1));
      expect(segs.first.words.length, words.length);
    });

    test('preserves globalStartWordIndex when starting mid-document', () {
      const text = 'Oración primera bastante larga aquí. '
          'Oración segunda también larga aquí muy clara.';
      final words = wordsOf(text);
      final segs = DeviceTtsRepository.splitIntoSentences(text, words, 1000);
      expect(segs.first.globalStartWordIndex, 1000);
      if (segs.length > 1) {
        expect(
          segs[1].globalStartWordIndex,
          1000 + segs[0].words.length,
        );
      }
    });

    test('falls back to splitIntoSegments when text has no punctuation', () {
      const text = 'sin puntuación alguna en este flujo de palabras lineales';
      final words = wordsOf(text);
      final segs = DeviceTtsRepository.splitIntoSentences(text, words, 0);
      expect(segs, hasLength(1));
      expect(segs.first.words.length, words.length);
    });

    test('empty input falls back to splitIntoSegments behaviour', () {
      // splitIntoSegments returns a single empty SpeakSegment for empty
      // input rather than an empty list; splitIntoSentences delegates to
      // it so the caller sees the same shape on this edge case.
      final segs = DeviceTtsRepository.splitIntoSentences('', const [], 0);
      expect(segs, hasLength(1));
      expect(segs.first.words, isEmpty);
      expect(segs.first.text, isEmpty);
    });

    test('words slice matches text content for each segment', () {
      const text =
          'La primera oración es bastante específica y única en su forma. '
          'La segunda oración también es distinta y reconocible al instante. '
          'La tercera oración cierra este bloque con cierta elegancia.';
      final words = wordsOf(text);
      final segs = DeviceTtsRepository.splitIntoSentences(text, words, 0);
      // Reconstruct the join of segment words and compare to original.
      final reconstructed = segs.expand((s) => s.words).join(' ');
      expect(reconstructed, words.join(' '));
    });

    test('audibleCharCount is populated for number-containing segments', () {
      const text = 'En el año 1967 ocurrieron eventos importantes en la ciudad. '
          'La gente recuerda esa época con nostalgia y cierta melancolía.';
      final words = wordsOf(text);
      final segs = DeviceTtsRepository.splitIntoSentences(text, words, 0);
      final firstNum = segs.firstWhere((s) => s.hasNumbers, orElse: () => segs.first);
      // audibleCharCount expands "1967" → "mil novecientos sesenta y siete"
      // so it should exceed the raw char count for that segment.
      expect(firstNum.audibleCharCount, greaterThan(firstNum.text.length));
    });
  });
}
