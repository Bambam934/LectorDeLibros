import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/device_tts_repository.dart';

/// Pure-function tests for the auto-recovery branching (FIX 33).
/// The full error handler also touches state/streams/completers, but the
/// decision of "recover vs escalate" is captured by [shouldAutoRecover],
/// which is what we validate here.
void main() {
  group('DeviceTtsRepository.shouldAutoRecover (FIX 33)', () {
    test('"interrupted" without user-stop and retries=0 → recover', () {
      expect(
        DeviceTtsRepository.shouldAutoRecover(
          errorMessage: 'interrupted',
          userRequestedStop: false,
          retryCount: 0,
        ),
        isTrue,
      );
    });

    test('"interrupted" message embedded in a longer string still triggers '
        'recovery (e.g. "speech interrupted by browser")', () {
      expect(
        DeviceTtsRepository.shouldAutoRecover(
          errorMessage: 'speech interrupted by browser',
          userRequestedStop: false,
          retryCount: 0,
        ),
        isTrue,
      );
    });

    test('"interrupted" + userRequestedStop → escalate (do NOT recover)', () {
      expect(
        DeviceTtsRepository.shouldAutoRecover(
          errorMessage: 'interrupted',
          userRequestedStop: true,
          retryCount: 0,
        ),
        isFalse,
        reason: 'When the user causes the stop, the resulting interrupt is '
            'expected and must NOT be auto-retried.',
      );
    });

    test('non-interrupt errors are never auto-recovered', () {
      expect(
        DeviceTtsRepository.shouldAutoRecover(
          errorMessage: 'language-not-supported',
          userRequestedStop: false,
          retryCount: 0,
        ),
        isFalse,
      );
      expect(
        DeviceTtsRepository.shouldAutoRecover(
          errorMessage: 'network',
          userRequestedStop: false,
          retryCount: 0,
        ),
        isFalse,
      );
    });

    test('null and empty error messages are treated as non-recoverable', () {
      expect(
        DeviceTtsRepository.shouldAutoRecover(
          errorMessage: null,
          userRequestedStop: false,
          retryCount: 0,
        ),
        isFalse,
      );
      expect(
        DeviceTtsRepository.shouldAutoRecover(
          errorMessage: '',
          userRequestedStop: false,
          retryCount: 0,
        ),
        isFalse,
      );
    });

    test('retry budget is respected: at maxRetries no further recovery', () {
      expect(
        DeviceTtsRepository.shouldAutoRecover(
          errorMessage: 'interrupted',
          userRequestedStop: false,
          retryCount: 2,
          maxRetries: 2,
        ),
        isFalse,
      );
    });

    test('one retry remaining still triggers recovery', () {
      expect(
        DeviceTtsRepository.shouldAutoRecover(
          errorMessage: 'interrupted',
          userRequestedStop: false,
          retryCount: 1,
          maxRetries: 2,
        ),
        isTrue,
      );
    });
  });
}
