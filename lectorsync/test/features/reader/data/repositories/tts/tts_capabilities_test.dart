import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/tts/tts_capabilities.dart';

void main() {
  group('TtsCapabilities.maxUtteranceChars (FIX 31)', () {
    test('mobile cap is generous (>= 4000) — Android/iOS engines tolerate '
        'long utterances comfortably', () {
      expect(TtsCapabilities.mobile.maxUtteranceChars,
          greaterThanOrEqualTo(4000));
    });

    test('web cap stays well under Chrome\'s empirical interrupt threshold '
        'of ~200 chars', () {
      expect(TtsCapabilities.web.maxUtteranceChars, lessThanOrEqualTo(200));
      expect(TtsCapabilities.web.maxUtteranceChars,
          greaterThan(0),
          reason: 'A non-positive cap would disable splitting entirely.');
    });

    test('copyWith preserves cap when not overridden', () {
      final modified =
          TtsCapabilities.web.copyWith(supportsWordBoundary: true);
      expect(modified.maxUtteranceChars, TtsCapabilities.web.maxUtteranceChars);
    });

    test('copyWith honours an explicit maxUtteranceChars override (used by '
        'Safari detection in WebTtsAdapter)', () {
      final safari = TtsCapabilities.web.copyWith(maxUtteranceChars: 100);
      expect(safari.maxUtteranceChars, 100);
      // Other fields should not be perturbed.
      expect(safari.supportsVoiceSelection,
          TtsCapabilities.web.supportsVoiceSelection);
      expect(safari.needsVoicesRetry, TtsCapabilities.web.needsVoicesRetry);
    });
  });
}
