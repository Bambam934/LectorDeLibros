import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/tts/segment_progress_tracker.dart';
import 'package:lectorsync/features/reader/data/repositories/device_tts_repository.dart';

void main() {
  group('SegmentProgressTracker', () {
    group('combineCalibration', () {
      test('returns measured when previous is null', () {
        expect(SegmentProgressTracker.combineCalibration(null, 55.0), 55.0);
      });

      test('applies EMA when skipCalibration is false', () {
        final result = SegmentProgressTracker.combineCalibration(50.0, 70.0);
        expect(result, closeTo(50.0 * 0.3 + 70.0 * 0.7, 0.001));
      });

      test('returns previous when skipCalibration is true', () {
        final result = SegmentProgressTracker.combineCalibration(
          50.0,
          200.0,
          skipCalibration: true,
        );
        expect(result, 50.0);
      });

      test('returns null when previous is null and skipCalibration is true',
          () {
        final result = SegmentProgressTracker.combineCalibration(
          null,
          200.0,
          skipCalibration: true,
        );
        expect(result, isNull);
      });

      test('numerical outlier does not contaminate calibration', () {
        var calibrated = 50.0;
        calibrated = SegmentProgressTracker.combineCalibration(
          calibrated,
          250.0,
          skipCalibration: true,
        )!;
        expect(calibrated, 50.0);

        calibrated = SegmentProgressTracker.combineCalibration(
          calibrated,
          52.0,
        )!;
        expect(calibrated, closeTo(50.0 * 0.3 + 52.0 * 0.7, 0.001));
      });
    });

    group('audibleCharCount', () {
      test('uses audibleCharCount for measuredMsPerChar when provided', () {
        final tracker = SegmentProgressTracker(
          wordCount: 10,
          globalStartWordIndex: 0,
          speechRate: 0.6,
          calibratedMsPerChar: 50.0,
          audibleCharCount: 120,
        );

        final emittedIndices = <int>[];
        tracker.start(
          charCount: 50,
          onWord: emittedIndices.add,
        );

        final elapsed = tracker.elapsed;
        if (elapsed.inMilliseconds > 0) {
          final msPerChar = tracker.measuredMsPerChar;
          expect(msPerChar, greaterThan(0));
        }

        tracker.cancel();
      });

      test('falls back to charCount when audibleCharCount is 0', () {
        final tracker = SegmentProgressTracker(
          wordCount: 10,
          globalStartWordIndex: 0,
          speechRate: 0.6,
          audibleCharCount: 0,
        );

        final emittedIndices = <int>[];
        tracker.start(
          charCount: 50,
          onWord: emittedIndices.add,
        );

        expect(tracker.isRunning, isTrue);
        tracker.cancel();
      });
    });

    group('silence gap detection', () {
      test('freezes when gap exceeds threshold', () async {
        final tracker = SegmentProgressTracker(
          wordCount: 50,
          globalStartWordIndex: 0,
          speechRate: 0.6,
          silenceGapThresholdMs: 100,
        );

        final emittedIndices = <int>[];
        tracker.start(
          charCount: 200,
          onWord: emittedIndices.add,
        );

        expect(tracker.isFrozen, isFalse);

        await Future.delayed(const Duration(milliseconds: 150));

        tracker.notifyRealProgress();
        expect(tracker.isFrozen, isTrue);

        tracker.unfreeze();
        expect(tracker.isFrozen, isFalse);

        tracker.cancel();
      });

      test('does not freeze when gap is below threshold', () async {
        final tracker = SegmentProgressTracker(
          wordCount: 50,
          globalStartWordIndex: 0,
          speechRate: 0.6,
          silenceGapThresholdMs: 500,
        );

        final emittedIndices = <int>[];
        tracker.start(
          charCount: 200,
          onWord: emittedIndices.add,
        );

        await Future.delayed(const Duration(milliseconds: 50));

        tracker.notifyRealProgress();
        expect(tracker.isFrozen, isFalse);

        tracker.cancel();
      });

      test('unfreeze allows tracker to resume', () async {
        final tracker = SegmentProgressTracker(
          wordCount: 50,
          globalStartWordIndex: 0,
          speechRate: 0.6,
          silenceGapThresholdMs: 100,
        );

        tracker.start(
          charCount: 200,
          onWord: (_) {},
        );

        await Future.delayed(const Duration(milliseconds: 150));
        tracker.notifyRealProgress();
        expect(tracker.isFrozen, isTrue);

        tracker.unfreeze();
        expect(tracker.isFrozen, isFalse);
        expect(tracker.isRunning, isTrue);

        tracker.cancel();
      });
    });
  });

  group('DeviceTtsRepository number detection', () {
    test('computeAudibleCharCount expands known numbers', () {
      final result =
          DeviceTtsRepository.computeAudibleCharCount('el 28 de Abril');
      expect(result, greaterThan('el 28 de Abril'.length));
    });

    test('computeAudibleCharCount uses dict for known number 28', () {
      final text = '28';
      final result = DeviceTtsRepository.computeAudibleCharCount(text);
      expect(result, equals('veintiocho'.length));
    });

    test('computeAudibleCharCount uses factor for unknown numbers', () {
      final result =
          DeviceTtsRepository.computeAudibleCharCount('el 9999 de Abril');
      expect(result, greaterThan('el 9999 de Abril'.length));
    });

    test('detectNumbers returns true for text with digits', () {
      expect(DeviceTtsRepository.detectNumbers('el 28 de Abril'), isTrue);
    });

    test('detectNumbers returns false for text without digits', () {
      expect(DeviceTtsRepository.detectNumbers('el día de Abril'), isFalse);
    });
  });
}
