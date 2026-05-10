import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/device_tts_repository.dart';

/// Builds a SpeakSegment from a single contiguous text. Words are derived by
/// splitting on whitespace, which mirrors how the upstream pipeline produces
/// them for Spanish prose.
SpeakSegment _seg(String text, {int globalStart = 0}) {
  final words = text.split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  return SpeakSegment(
    text: text,
    words: words,
    globalStartWordIndex: globalStart,
    audibleCharCount: text.length,
    hasNumbers: RegExp(r'\d').hasMatch(text),
  );
}

void main() {
  group('DeviceTtsRepository.enforceMaxSegmentLength', () {
    test('passes through segments already under the limit', () {
      final input = [_seg('Hola mundo, esto cabe.', globalStart: 0)];
      final out = DeviceTtsRepository.enforceMaxSegmentLength(input, 180);
      expect(out, hasLength(1));
      expect(out.first.text, input.first.text);
      expect(out.first.words, input.first.words);
      expect(out.first.globalStartWordIndex, 0);
    });

    test('splits a long Chrome-overflow segment (~2382 chars) into chunks all '
        'under maxChars=180 with at least 14 sub-segments (FIX 32)', () {
      // Build a realistic-looking ~2382 char segment with commas, periods,
      // and spaces — the natural break candidates the splitter prefers.
      final buffer = StringBuffer();
      var wordCount = 0;
      while (buffer.length < 2382) {
        buffer.write(
          'palabra${wordCount.toString().padLeft(4, '0')} ',
        );
        wordCount++;
        if (wordCount % 8 == 0) buffer.write(', ');
        if (wordCount % 25 == 0) buffer.write('. ');
      }
      final text = buffer.toString().substring(0, 2382);
      final words = text.split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      final input = [
        SpeakSegment(
          text: text,
          words: words,
          globalStartWordIndex: 0,
          audibleCharCount: text.length,
          hasNumbers: false,
        ),
      ];

      final out = DeviceTtsRepository.enforceMaxSegmentLength(input, 180);

      expect(out.length, greaterThanOrEqualTo(14),
          reason: 'A 2382-char segment with maxChars=180 must produce '
              'at least 14 sub-segments (2382/180 = 13.2 — round up).');
      for (final s in out) {
        expect(s.text.length, lessThanOrEqualTo(180),
            reason: 'No sub-segment may exceed maxChars=180.');
        expect(s.words, isNotEmpty,
            reason: 'Every sub-segment must own at least one word.');
      }
    });

    test('preserves contiguous globalStartWordIndex coverage of source words '
        '(no overlaps, no gaps)', () {
      // Use a segment whose word boundaries are unambiguous.
      final words = List<String>.generate(60, (i) => 'w$i');
      final text = words.join(' ');
      final input = [
        SpeakSegment(
          text: text,
          words: words,
          globalStartWordIndex: 100, // arbitrary global offset
          audibleCharCount: text.length,
          hasNumbers: false,
        ),
      ];

      final out = DeviceTtsRepository.enforceMaxSegmentLength(input, 50);

      // Concatenated word count must equal original word count.
      final totalWords = out.fold<int>(0, (a, s) => a + s.words.length);
      expect(totalWords, words.length);

      // Sub-segments must be contiguous: each starts where the previous
      // ended.
      var expectedStart = 100;
      for (final s in out) {
        expect(s.globalStartWordIndex, expectedStart,
            reason: 'Sub-segments must form a contiguous global index range.');
        expectedStart += s.words.length;
      }
      expect(expectedStart, 100 + words.length);
    });

    test('prefers a comma break over a hard cut when one is available', () {
      // Construct text where a comma sits inside the budget but a space
      // sits even closer to the limit. The splitter must still pick the
      // comma so the break lands on a natural pause.
      const text = 'aaaaaaaaaa, bbbbbbbbbb cccccccccc dddddddddd';
      // length 44; with maxChars=15 the budget [0,15] contains the comma at
      // index 10 AND the space at index 11. Comma is preferred.
      final input = [
        SpeakSegment(
          text: text,
          words: text.split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .toList(),
          globalStartWordIndex: 0,
          audibleCharCount: text.length,
          hasNumbers: false,
        ),
      ];

      final out = DeviceTtsRepository.enforceMaxSegmentLength(input, 15);

      expect(out.length, greaterThan(1));
      // Chunk includes the comma itself but not the trailing space.
      expect(out.first.text, 'aaaaaaaaaa,',
          reason: 'First chunk must end exactly at the comma break.');
    });

    test('falls back to hard cut when no comma or space fits in the budget',
        () {
      // Single 200-char "word" with no whitespace inside the budget.
      final text = 'x' * 200;
      final input = [
        SpeakSegment(
          text: text,
          words: [text],
          globalStartWordIndex: 0,
          audibleCharCount: text.length,
          hasNumbers: false,
        ),
      ];

      final out = DeviceTtsRepository.enforceMaxSegmentLength(input, 50);

      expect(out.length, greaterThanOrEqualTo(4));
      for (final s in out) {
        expect(s.text.length, lessThanOrEqualTo(50));
      }
      // The single word is force-attached to every chunk (per the
      // "at least one word" guarantee), but the chunked text covers the
      // whole 200-char source.
      final reassembled = out.map((s) => s.text).join();
      expect(reassembled, text);
    });

    test('REGRESSION — comma exactly at hardLimit must NOT push the chunk '
        'to maxChars+1 (off-by-one observed in production: 181 > 180)', () {
      // Construct a 200-char segment with a comma at position 179 (so
      // hardLimit=180 sees the comma at hardLimit-1). Without the fix
      // the splitter would produce a 181-char chunk because it
      // included the comma at position 180 → chunkEnd = 181.
      final filler = 'a' * 179;
      final text = '$filler, ${'b' * 19}'; // 179 + 2 + 19 = 200
      final input = [
        SpeakSegment(
          text: text,
          words: text.split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .toList(),
          globalStartWordIndex: 0,
          audibleCharCount: text.length,
          hasNumbers: false,
        ),
      ];

      final out = DeviceTtsRepository.enforceMaxSegmentLength(input, 180);

      for (final s in out) {
        expect(s.text.length, lessThanOrEqualTo(180),
            reason: 'No sub-segment may exceed maxChars=180 — even when '
                'a comma sits at exactly hardLimit.');
      }
    });

    test('REGRESSION — every position of a comma in [hardLimit-1 .. hardLimit] '
        'is covered: chunk stays <= maxChars regardless', () {
      for (var commaPos = 175; commaPos <= 181; commaPos++) {
        final before = 'a' * commaPos;
        final after = 'b' * (200 - commaPos - 1);
        final text = '$before,$after';
        final input = [
          SpeakSegment(
            text: text,
            words: [before, after],
            globalStartWordIndex: 0,
            audibleCharCount: text.length,
            hasNumbers: false,
          ),
        ];

        final out = DeviceTtsRepository.enforceMaxSegmentLength(input, 180);
        for (final s in out) {
          expect(s.text.length, lessThanOrEqualTo(180),
              reason: 'commaPos=$commaPos produced a chunk of '
                  '${s.text.length} chars, exceeding 180.');
        }
      }
    });

    test('returns the input unchanged when maxChars <= 0 (defensive)', () {
      final input = [_seg('hola mundo')];
      final out = DeviceTtsRepository.enforceMaxSegmentLength(input, 0);
      expect(out, same(input));
    });
  });
}
