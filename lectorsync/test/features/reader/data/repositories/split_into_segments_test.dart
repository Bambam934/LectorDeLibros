import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/device_tts_repository.dart';

/// Unit tests for [DeviceTtsRepository.splitIntoSegments].
///
/// The previous implementation used `text.indexOf(lastWord, charCursor)` to
/// find the end of each word-based segment. This performs a **substring**
/// match, so a common word like "de" was found inside "del" at position 0,
/// truncating the segment text to 2 chars for 200 words.
///
/// These tests verify the fix: pre-computing char positions for every word
/// using a sequential cursor, then using those positions to slice the text.
void main() {
  /// Helper: tokenize text the same way Chapter._tokenizeWords does.
  List<String> tokenize(String text) =>
      text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  group('splitIntoSegments — text/words alignment', () {
    test('single segment (≤ maxWords) returns full text unchanged', () {
      const text = 'del 28 de Abril de 1967 llevaba dos días.';
      final words = tokenize(text);
      final segments = DeviceTtsRepository.splitIntoSegments(
        text, words, 0,
        maxWords: 200,
      );

      expect(segments, hasLength(1));
      expect(segments[0].text, text);
      expect(segments[0].words, words);
      expect(segments[0].globalStartWordIndex, 0);
    });

    test('OLD BUG: "de" found inside "del" — segment text must NOT be '
        'truncated to 2 chars', () {
      // Construct text where word at maxWords-1 is "de" and "de" appears
      // earlier as a substring of "del".
      final buffer = StringBuffer('del 28 de Abril de 1967 ');
      // Pad with enough words so total > maxWords=5
      buffer.write('uno dos tres cuatro cinco seis siete ocho');
      final text = buffer.toString();
      final words = tokenize(text);

      // With maxWords=5, segment 0 has words[0..4] = [del, 28, de, Abril, de]
      // The old code did text.indexOf("de", 0) → position 0 (inside "del")
      // → segmentText = "de" (2 chars for 5 words).
      final segments = DeviceTtsRepository.splitIntoSegments(
        text, words, 0,
        maxWords: 5,
      );

      expect(segments.length, greaterThanOrEqualTo(2));

      // Segment 0 must contain all 5 words AND their corresponding text.
      final seg0 = segments[0];
      expect(seg0.words.length, 5);
      expect(seg0.words, ['del', '28', 'de', 'Abril', 'de']);
      // Text must span from "del" to "de" (the 5th word), not just "de".
      expect(seg0.text.length, greaterThan(10),
          reason: 'Segment text must span all 5 words, '
              'not be truncated to the first substring match.');
      // Verify every word is actually IN the segment text.
      for (final w in seg0.words) {
        expect(seg0.text.contains(w), isTrue,
            reason: 'Word "$w" must be found in segment text "${seg0.text}"');
      }
    });

    test('globalStartWordIndex is correct for multi-segment split', () {
      // Build text with 12 words.
      const text = 'uno dos tres cuatro cinco seis siete ocho nueve diez once doce';
      final words = tokenize(text);
      expect(words.length, 12);

      final segments = DeviceTtsRepository.splitIntoSegments(
        text, words, 10,
        maxWords: 5,
      );

      // 12 words / 5 per segment = 3 segments (5, 5, 2).
      expect(segments, hasLength(3));
      expect(segments[0].globalStartWordIndex, 10);
      expect(segments[0].words.length, 5);
      expect(segments[1].globalStartWordIndex, 15);
      expect(segments[1].words.length, 5);
      expect(segments[2].globalStartWordIndex, 20);
      expect(segments[2].words.length, 2);
    });

    test('segment text preserves original whitespace and punctuation', () {
      // Text with newlines between paragraphs (as in a real chapter).
      const text =
          'Primer párrafo con texto.\n\nSegundo párrafo diferente.\n\nTercer párrafo final.';
      final words = tokenize(text);

      final segments = DeviceTtsRepository.splitIntoSegments(
        text, words, 0,
        maxWords: 4,
      );

      // Each segment's text should be a substring of the original.
      for (final seg in segments) {
        expect(
          text.contains(seg.text),
          isTrue,
          reason:
              'Segment text "${seg.text}" must be a substring of the original.',
        );
      }

      // Concatenation of all segment texts should cover the full text
      // (may have gaps for inter-segment whitespace, but words must be
      // contiguous within each segment).
      final allWords = segments.expand((s) => s.words).toList();
      expect(allWords, words);
    });

    test('duplicate phrases across paragraphs produce correct alignment', () {
      // The exact bug scenario: "28 de Abril" appears in two paragraphs.
      const text =
          'El del 28 de Abril llevaba dos días siendo asediado. '
          'Otro párrafo intermedio con varias palabras más aquí. '
          'El del 28 de Abril se celebró la fiesta grande.';
      final words = tokenize(text);

      final segments = DeviceTtsRepository.splitIntoSegments(
        text, words, 0,
        maxWords: 10,
      );

      // Every segment must have text that contains ALL its words.
      for (var i = 0; i < segments.length; i++) {
        final seg = segments[i];
        // Build char offsets the same way the real code does.
        final offsets = <int>[];
        int cursor = 0;
        for (final w in seg.words) {
          final idx = seg.text.indexOf(w, cursor);
          expect(idx, greaterThanOrEqualTo(0),
              reason: 'Word "$w" (segment $i) must be found in '
                  'segment text "${seg.text}" at cursor=$cursor');
          offsets.add(idx);
          cursor = idx + w.length;
        }
        // Offsets must be strictly non-decreasing.
        for (var j = 1; j < offsets.length; j++) {
          expect(offsets[j], greaterThanOrEqualTo(offsets[j - 1]),
              reason: 'Char offsets must be non-decreasing in segment $i');
        }
      }
    });

    test('words with common substrings (de/del, el/él) do not cause '
        'false indexOf matches', () {
      const text = 'del pueblo de la aldea el camino del bosque de niebla';
      final words = tokenize(text);

      // With maxWords=5: [del, pueblo, de, la, aldea] | [el, camino, del, bosque, de] | [niebla]
      final segments = DeviceTtsRepository.splitIntoSegments(
        text, words, 0,
        maxWords: 5,
      );

      // Segment 0 should span "del pueblo de la aldea"
      expect(segments[0].text, contains('pueblo'));
      expect(segments[0].text, contains('aldea'));
      expect(segments[0].words, ['del', 'pueblo', 'de', 'la', 'aldea']);

      // Segment 1 should span "el camino del bosque de"
      expect(segments[1].text, contains('camino'));
      expect(segments[1].text, contains('bosque'));
      expect(segments[1].words, ['el', 'camino', 'del', 'bosque', 'de']);
    });

    test('empty text fallback: segment text = words.join(" ")', () {
      final words = ['uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis'];
      final segments = DeviceTtsRepository.splitIntoSegments(
        '', words, 0,
        maxWords: 3,
      );

      expect(segments, hasLength(2));
      expect(segments[0].text, 'uno dos tres');
      expect(segments[1].text, 'cuatro cinco seis');
    });

    test('hasNumbers flag is per-segment, not global', () {
      const text = 'palabra sin números y otra más. Aquí hay 42 gatos lindos.';
      final words = tokenize(text);

      final segments = DeviceTtsRepository.splitIntoSegments(
        text, words, 0,
        maxWords: 6,
      );

      expect(segments.length, greaterThanOrEqualTo(2));
      // First segment: "palabra sin números y otra más." → no digits
      expect(segments[0].hasNumbers, isFalse);
      // Second segment contains "42" → has digits
      expect(segments[1].hasNumbers, isTrue);
    });
  });
}
