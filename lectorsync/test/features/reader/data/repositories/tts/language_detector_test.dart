import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/tts/language_detector.dart';

/// Tests the lightweight frequency-based language detector used by
/// DeviceTtsRepository when `autoLanguageEnabled` is true and no voice
/// has been manually selected.
void main() {
  group('LanguageDetector', () {
    test('detects Spanish from common words', () {
      final result = LanguageDetector.detect(
        'En el bosque vivía una niña que se llamaba Caperucita. '
        'Cuando salía por las mañanas para visitar a su abuela, '
        'siempre llevaba una cesta con comida.',
      );
      expect(result.startsWith('es'), isTrue);
    });

    test('detects English from common words', () {
      final result = LanguageDetector.detect(
        'The quick brown fox jumps over the lazy dog. This is a test '
        'sentence that should be detected as English by the detector.',
      );
      expect(result.startsWith('en'), isTrue);
    });

    test('detects French from common words', () {
      final result = LanguageDetector.detect(
        'Le petit prince habite sur une planète. Il aime sa rose et '
        'voyage à travers les étoiles pour la retrouver.',
      );
      expect(result.startsWith('fr'), isTrue);
    });

    test('detects Portuguese from common words', () {
      final result = LanguageDetector.detect(
        'O pequeno príncipe vive em um planeta. Ele ama a sua rosa e '
        'viaja pelas estrelas para a encontrar novamente.',
      );
      expect(result.startsWith('pt'), isTrue);
    });

    test('returns a language for empty input', () {
      // Should not throw; falls back to a default.
      final result = LanguageDetector.detect('');
      expect(result, isA<String>());
      expect(result.length, greaterThanOrEqualTo(2));
    });

    test('returns a language for unknown text', () {
      // Random characters — detector should still return something
      // (defaulting rather than throwing).
      final result = LanguageDetector.detect('xqz blrk znm pqz');
      expect(result, isA<String>());
    });
  });
}
