import 'speak_segment.dart';

/// Lógica **pura** de segmentación de texto para el pipeline TTS.
///
/// Extraído de `DeviceTtsRepository` (2026-07-19): todo lo de aquí son
/// funciones sin estado ni dependencia del engine, por lo que se pueden
/// testear en aislamiento. El motor (estado, timing, tracker, retries)
/// permanece en `device_tts_repository.dart`, que re-expone estas
/// funciones como miembros estáticos para no romper a sus llamadores.

/// Tope de palabras por utterance en la segmentación base.
const int kMaxWordsPerSegment = 200;

/// Presupuesto de reintentos por segmento ante errores "interrupted".
const int kMaxSegmentRetries = 2;

final digitRegex = RegExp(r'\d+');

const numberExpansionFactor = 4;

const numberExpansionDict = <String, String>{
  '28': 'veintiocho',
  '1967': 'mil novecientos sesenta y siete',
  '1': 'uno',
  '2': 'dos',
  '3': 'tres',
  '4': 'cuatro',
  '5': 'cinco',
  '6': 'seis',
  '7': 'siete',
  '8': 'ocho',
  '9': 'nueve',
  '10': 'diez',
  '11': 'once',
  '12': 'doce',
  '13': 'trece',
  '14': 'catorce',
  '15': 'quince',
  '16': 'dieciséis',
  '17': 'diecisiete',
  '18': 'dieciocho',
  '19': 'diecinueve',
  '20': 'veinte',
  '30': 'treinta',
  '40': 'cuarenta',
  '50': 'cincuenta',
  '60': 'sesenta',
  '70': 'setenta',
  '80': 'ochenta',
  '90': 'noventa',
  '100': 'cien',
  '200': 'doscientos',
  '500': 'quinientos',
  '1000': 'mil',
};

/// Cuenta caracteres *audibles*: los dígitos se expanden a su lectura en
/// español porque el engine tarda mucho más en pronunciar "1967" que sus
/// 4 caracteres, y la calibración ms/char quedaría sesgada.
int computeAudibleCharCount(String text) {
  var count = 0;
  var cursor = 0;
  while (cursor < text.length) {
    final match = digitRegex.matchAsPrefix(text, cursor);
    if (match != null) {
      final numStr = match.group(0)!;
      final expanded = numberExpansionDict[numStr];
      count += expanded != null ? expanded.length : numStr.length * numberExpansionFactor;
      cursor = match.end;
    } else {
      count++;
      cursor++;
    }
  }
  return count;
}

bool detectNumbers(String text) => digitRegex.hasMatch(text);

/// Splits words into segments of up to [maxWords] words, preserving the
/// original text alignment.  Exposed as a static method so unit tests
/// can validate the splitting without standing up the full pipeline.
List<SpeakSegment> splitIntoSegments(
  String text,
  List<String> words,
  int globalStartIndex, {
  int maxWords = kMaxWordsPerSegment,
}) {
  if (words.length <= maxWords) {
    final segText = text.isEmpty ? words.join(' ') : text;
    return [
      SpeakSegment(
        text: segText,
        words: words,
        globalStartWordIndex: globalStartIndex,
        audibleCharCount: computeAudibleCharCount(segText),
        hasNumbers: detectNumbers(segText),
      ),
    ];
  }

  // FIX — pre-compute char positions for EVERY word using sequential
  // cursor-based indexOf.  The previous code searched only for the
  // segment's *last* word with `text.indexOf(lastWord, charCursor)`,
  // which performs a **substring** match.  For common Spanish words
  // like "de", this found "de" inside "del" at position 0, truncating
  // the segment text to 2 chars for 200 words.  The resulting
  // text/words mismatch caused `_buildCharOffsets` to map most words
  // to the same offset, making `_binarySearch` return erratic indices
  // (the "se salta varios párrafos" highlight jump to a paragraph
  // with identical text).
  final wordCharPositions = <int>[];
  final wordCharEnds = <int>[];
  {
    int cursor = 0;
    for (final w in words) {
      final idx = text.indexOf(w, cursor);
      if (idx >= 0) {
        wordCharPositions.add(idx);
        wordCharEnds.add(idx + w.length);
        cursor = idx + w.length;
      } else {
        // Word not found — anchor it at cursor so subsequent words
        // still search from the right position.
        wordCharPositions.add(cursor);
        wordCharEnds.add(cursor);
      }
    }
  }

  final segments = <SpeakSegment>[];
  int wordCursor = 0;

  while (wordCursor < words.length) {
    final endWord = (wordCursor + maxWords).clamp(0, words.length);
    final segmentWords = words.sublist(wordCursor, endWord);

    String segmentText;
    if (text.isNotEmpty) {
      final charStart = wordCharPositions[wordCursor];
      final charEnd = wordCharEnds[endWord - 1];

      if (charStart < text.length && charEnd > charStart) {
        segmentText = text.substring(charStart, charEnd);
      } else {
        segmentText = segmentWords.join(' ');
      }
    } else {
      segmentText = segmentWords.join(' ');
    }

    // Defensive: log if the segment text is suspiciously short
    // relative to its word count (would mean a mapping problem).
    assert(
      segmentText.length >= segmentWords.length || segmentWords.isEmpty,
      '[_splitIntoSegments] segment text too short: '
      '${segmentText.length} chars for ${segmentWords.length} words',
    );

    segments.add(
      SpeakSegment(
        text: segmentText,
        words: segmentWords,
        globalStartWordIndex: globalStartIndex + wordCursor,
        audibleCharCount: computeAudibleCharCount(segmentText),
        hasNumbers: detectNumbers(segmentText),
      ),
    );
    wordCursor = endWord;
  }

  return segments;
}

/// FIX 78 (session 16) — Sentence-aligned segmentation.
///
/// The single largest source of perceived desync between the highlight
/// and the spoken audio on Windows SAPI5 and Web Speech is that those
/// engines insert *natural* pauses at sentence-ending punctuation
/// (`.`, `!`, `?`, `;`) — anywhere from ~150 ms (semicolon) up to
/// ~500 ms (period followed by paragraph break). The timer-based
/// SegmentProgressTracker has no way to know about those pauses: it
/// keeps advancing at the estimated ms/word rate, so once the engine
/// has paused N times mid-segment the highlight is N×~300 ms ahead of
/// the voice. With a single 800-char (~130-word) Windows segment that
/// contains 5–8 sentences, the cumulative drift exceeds three words
/// before the segment ends — which the user perceives as "totally
/// desynchronised" right after the first paragraph.
///
/// The industry-standard fix used by Voice Dream Reader, NaturalReader
/// on Windows, and Speechify when running on top of SAPI5 / Web Speech
/// is to give each *sentence* its own utterance:
///
///   • The engine's pause coincides with the boundary between two of
///     OUR segments, where the tracker is destroyed and recreated for
///     the next sentence — the pause is absorbed for free.
///   • Calibration error cannot accumulate across sentences, because
///     the tracker resets at every boundary.
///   • The next sentence's tracker is fully re-seeded with the last
///     calibrated ms/char, so it starts already tuned.
///
/// This method splits `text` at sentence-ending punctuation followed
/// by whitespace, while keeping each segment's `words` slice aligned
/// with the original word list (so the highlight follower keeps
/// working). Very short fragments (<30 chars, e.g. "Sí.") are merged
/// with their neighbour to avoid choppy speech and excessive engine
/// thrash. If the source text has no punctuation at all (some
/// poetry, weird OCR output), the whole input is returned as a single
/// segment and the existing `enforceMaxSegmentLength` will cap it.
List<SpeakSegment> splitIntoSentences(
  String text,
  List<String> words,
  int globalStartIndex, {
  int minMergeChars = 30,
}) {
  if (text.isEmpty || words.isEmpty) {
    return splitIntoSegments(text, words, globalStartIndex);
  }

  // Map each word to its char span in `text` (sequential cursor-based
  // search, same logic as splitIntoSegments to avoid 'de' inside 'del'
  // false positives).
  final wordCharStart = <int>[];
  final wordCharEnd = <int>[];
  {
    int cursor = 0;
    for (final w in words) {
      final idx = text.indexOf(w, cursor);
      if (idx >= 0) {
        wordCharStart.add(idx);
        wordCharEnd.add(idx + w.length);
        cursor = idx + w.length;
      } else {
        wordCharStart.add(cursor);
        wordCharEnd.add(cursor);
      }
    }
  }

  // Sentence boundary = run of `.!?;` followed by whitespace or EOS.
  // We deliberately do NOT split on `,` or `:` here — the pauses
  // those introduce are short (~100 ms) and well within the tracker's
  // tolerance, while splitting on them would produce many tiny
  // segments and force the engine into staccato output.
  final boundaryRegex = RegExp(r'[\.!?;]+(?=\s|$)');

  final boundaries = <int>[];
  for (final m in boundaryRegex.allMatches(text)) {
    boundaries.add(m.end);
  }
  if (boundaries.isEmpty || boundaries.last < text.length) {
    boundaries.add(text.length);
  }

  final raw = <SpeakSegment>[];
  int charCursor = 0;
  int wordCursor = 0;

  for (final boundaryEnd in boundaries) {
    // Walk forward through words whose char start lies before the
    // boundary; those belong to this sentence.
    int wEnd = wordCursor;
    while (wEnd < words.length && wordCharStart[wEnd] < boundaryEnd) {
      wEnd++;
    }
    if (wEnd == wordCursor) {
      // Boundary fell BEFORE the next unconsumed word (e.g. leading
      // whitespace, repeated punctuation). Skip the char range and
      // keep going so we don't emit an empty segment.
      charCursor = boundaryEnd;
      continue;
    }
    final segText = text.substring(charCursor, boundaryEnd).trim();
    final segWords = words.sublist(wordCursor, wEnd);
    if (segText.isNotEmpty && segWords.isNotEmpty) {
      raw.add(SpeakSegment(
        text: segText,
        words: segWords,
        globalStartWordIndex: globalStartIndex + wordCursor,
        audibleCharCount: computeAudibleCharCount(segText),
        hasNumbers: detectNumbers(segText),
      ));
    }
    wordCursor = wEnd;
    charCursor = boundaryEnd;
  }

  if (raw.isEmpty) {
    return splitIntoSegments(text, words, globalStartIndex);
  }

  // Merge fragments shorter than `minMergeChars` with the next
  // segment. Avoids choppy "Sí." / "¿Eh?" utterances that produce
  // disproportionate engine latency.
  final merged = <SpeakSegment>[];
  SpeakSegment? buffer;
  for (final seg in raw) {
    if (buffer == null) {
      buffer = seg;
      continue;
    }
    if (buffer.text.length < minMergeChars) {
      final mergedText = '${buffer.text} ${seg.text}';
      final mergedWords = <String>[...buffer.words, ...seg.words];
      buffer = SpeakSegment(
        text: mergedText,
        words: mergedWords,
        globalStartWordIndex: buffer.globalStartWordIndex,
        audibleCharCount: computeAudibleCharCount(mergedText),
        hasNumbers: buffer.hasNumbers || seg.hasNumbers,
      );
    } else {
      merged.add(buffer);
      buffer = seg;
    }
  }
  if (buffer != null) merged.add(buffer);
  return merged;
}

/// True iff the given engine error message indicates an
/// "interrupted"-class failure (Web Speech overflow, native cancel).
bool isInterruptedMessage(Object? msg) {
  final s = msg?.toString() ?? '';
  if (s.isEmpty) return false;
  if (s == 'interrupted') return true;
  return s.toLowerCase().contains('interrupt');
}

/// FIX 33 — Pure predicate exposing the auto-recovery decision so unit
/// tests can validate the branching without a live FlutterTts engine.
///
/// Returns `true` iff:
///   * the engine reported an "interrupted"-class error, AND
///   * the user did NOT cause the stop (no in-flight stop()/setVoice()),
///     AND
///   * we still have recovery budget left ([retryCount] < [maxRetries]).
bool shouldAutoRecover({
  required Object? errorMessage,
  required bool userRequestedStop,
  required int retryCount,
  int maxRetries = kMaxSegmentRetries,
}) {
  if (!isInterruptedMessage(errorMessage)) return false;
  if (userRequestedStop) return false;
  if (retryCount >= maxRetries) return false;
  return true;
}

/// FIX 32 — Hard cap on per-utterance characters.
///
/// The base [splitIntoSegments] partitions by word count, which on Web
/// can still produce utterances of 2000+ chars (a single long paragraph).
/// `window.speechSynthesis.speak()` then silently fires
/// `SpeechSynthesisErrorEvent("interrupted")` once Chrome's empirical
/// limit (~200 chars) is exceeded. This pass walks each input segment
/// and emits sub-segments of `<= maxChars`, breaking on the rightmost
/// punctuation/space within the budget when possible.
///
/// The global word indices of the resulting sub-segments still map 1:1
/// to the original `words` list — sub-segments simply share contiguous
/// ranges so the highlight follower keeps working.
List<SpeakSegment> enforceMaxSegmentLength(
  List<SpeakSegment> segments,
  int maxChars,
) {
  if (maxChars <= 0) return segments;
  final result = <SpeakSegment>[];
  for (final seg in segments) {
    if (seg.text.length <= maxChars) {
      result.add(seg);
      continue;
    }

    // Build word offsets in the original text.
    final wordOffsets = <int>[];
    int cursor = 0;
    for (final w in seg.words) {
      final idx = seg.text.indexOf(w, cursor);
      if (idx >= 0) {
        wordOffsets.add(idx);
        cursor = idx + w.length;
      } else {
        wordOffsets.add(cursor);
      }
    }

    int charCursor = 0;
    int wordCursor = 0;

    while (charCursor < seg.text.length) {
      final remaining = seg.text.length - charCursor;
      int chunkEnd;
      if (remaining <= maxChars) {
        chunkEnd = seg.text.length;
      } else {
        final hardLimit = charCursor + maxChars;

        // FIX: search up to `hardLimit - 1` so that `breakAt + 1`
        // (which includes the punctuation/space char) is guaranteed
        // to be `<= hardLimit`. Without this clamp, a comma sitting
        // exactly at `hardLimit` produced a chunk of length
        // `maxChars + 1` and the per-utterance cap was silently
        // exceeded by 1 char (Chrome interrupted at 181 chars on a
        // 180-char cap).
        final searchLimit = hardLimit - 1;

        // 1) last comma before hardLimit
        var breakAt = seg.text.lastIndexOf(',', searchLimit);
        if (breakAt <= charCursor) breakAt = -1;

        // 2) fallback: last space before hardLimit
        if (breakAt < 0) {
          breakAt = seg.text.lastIndexOf(' ', searchLimit);
          if (breakAt <= charCursor) breakAt = -1;
        }

        // 3) hard cut at maxChars
        if (breakAt < 0) {
          chunkEnd = hardLimit;
        } else {
          chunkEnd = breakAt + 1; // include the comma/space char
        }
      }

      // Determine the word range for this chunk.
      int chunkStartWord;
      int chunkEndWord;
      if (wordCursor >= seg.words.length) {
        // We exhausted the word list (e.g. very long un-spaced word
        // that spans multiple chunks). Attach the trailing chunks to
        // the final word so the highlight follower stays put.
        if (seg.words.isEmpty) {
          chunkStartWord = 0;
          chunkEndWord = 0;
        } else {
          chunkStartWord = seg.words.length - 1;
          chunkEndWord = seg.words.length;
        }
      } else {
        chunkStartWord = wordCursor;
        var advanced = wordCursor;
        while (advanced < seg.words.length && wordOffsets[advanced] < chunkEnd) {
          advanced++;
        }
        if (advanced == chunkStartWord) {
          // Force-include at least one word so we never produce a
          // chunk with zero words (which would make the follower lose
          // the highlight).
          advanced = chunkStartWord + 1;
        }
        chunkEndWord = advanced;
        wordCursor = advanced;
      }

      final chunkWords = chunkEndWord > chunkStartWord
          ? seg.words.sublist(chunkStartWord, chunkEndWord)
          : const <String>[];
      final chunkText = seg.text.substring(charCursor, chunkEnd);

      result.add(
        SpeakSegment(
          text: chunkText,
          words: chunkWords,
          globalStartWordIndex: seg.globalStartWordIndex + chunkStartWord,
          audibleCharCount: computeAudibleCharCount(chunkText),
          hasNumbers: detectNumbers(chunkText),
        ),
      );

      charCursor = chunkEnd;
    }
  }
  return result;
}
