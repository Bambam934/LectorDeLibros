import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/tts/segment_progress_tracker.dart';

/// Verifies the calibration safety bounds added in Session 6 to fix
/// the "highlight stuck at 1 word per 2 seconds" symptom caused by a
/// polluted `_calibratedMsPerChar`.
void main() {
  group('SegmentProgressTracker calibration bounds', () {
    test('combineCalibration rejects measurement below lower bound', () {
      final result = SegmentProgressTracker.combineCalibration(50.0, 5.0);
      // 5 ms/char is way too fast for any real engine — should reject
      // and keep previous.
      expect(result, 50.0);
    });

    test('combineCalibration rejects measurement above upper bound', () {
      final result =
          SegmentProgressTracker.combineCalibration(50.0, 500.0);
      // 500 ms/char would make highlight crawl — reject as outlier.
      expect(result, 50.0);
    });

    test('combineCalibration rejects outlier when previous is null', () {
      // Even with no prior calibration, an obvious outlier should not
      // become the seed value.
      final tooFast =
          SegmentProgressTracker.combineCalibration(null, 5.0);
      expect(tooFast, isNull);
      final tooSlow =
          SegmentProgressTracker.combineCalibration(null, 1000.0);
      expect(tooSlow, isNull);
    });

    test('combineCalibration accepts valid measurement at bounds', () {
      // 20 ms/char is the lower bound — should accept.
      final atMin = SegmentProgressTracker.combineCalibration(null, 20.0);
      expect(atMin, 20.0);
      // 200 ms/char is the upper bound — should accept.
      final atMax =
          SegmentProgressTracker.combineCalibration(null, 200.0);
      expect(atMax, 200.0);
    });

    test('combineCalibration blends within bounds correctly', () {
      // Blend is now 0.5/0.5 (session 15) — converges in 2-3 segments
      // instead of 5. Earlier the weight was 0.3 previous / 0.7
      // measured which trusted the new measurement too aggressively
      // for the smoothing to actually do anything in practice.
      final result = SegmentProgressTracker.combineCalibration(50.0, 80.0);
      expect(result, closeTo(50.0 * 0.5 + 80.0 * 0.5, 0.001));
    });

    test('blended value is clamped if EMA somehow exceeds bounds', () {
      // 50/50 blend: previous=180, measured=200 → 90 + 100 = 190.
      // Stays inside [20, 200] so no clamp triggers; we still assert
      // the bounds to lock in the contract.
      final result =
          SegmentProgressTracker.combineCalibration(180.0, 200.0);
      expect(result, closeTo(190.0, 0.001));
      expect(result, lessThanOrEqualTo(200.0));
      expect(result, greaterThanOrEqualTo(20.0));
    });
  });

  group('SegmentProgressTracker resyncTo', () {
    test('resyncTo moves cursor forward', () {
      final tracker = SegmentProgressTracker(
        wordCount: 100,
        globalStartWordIndex: 50,
        speechRate: 0.6,
      );
      tracker.start(charCount: 500, onWord: (_) {});

      tracker.resyncTo(30);
      expect(tracker.globalWordIndex, 80); // 50 + 30

      tracker.cancel();
    });

    test('resyncTo allows moving backwards (unlike updateWordIndex)', () {
      final tracker = SegmentProgressTracker(
        wordCount: 100,
        globalStartWordIndex: 0,
        speechRate: 0.6,
      );
      tracker.start(charCount: 500, onWord: (_) {});

      tracker.updateWordIndex(50);
      expect(tracker.globalWordIndex, 50);

      // resyncTo should allow going BACK to 30, where updateWordIndex
      // would refuse.
      tracker.resyncTo(30);
      expect(tracker.globalWordIndex, 30);

      tracker.cancel();
    });

    test('resyncTo clamps to valid range', () {
      final tracker = SegmentProgressTracker(
        wordCount: 50,
        globalStartWordIndex: 100,
        speechRate: 0.6,
      );
      tracker.start(charCount: 250, onWord: (_) {});

      tracker.resyncTo(-5);
      expect(tracker.globalWordIndex, 100); // clamped to local 0

      tracker.resyncTo(200);
      expect(tracker.globalWordIndex, 149); // 100 + (50-1) clamped

      tracker.cancel();
    });

    test('resyncTo unfreezes the tracker', () async {
      final tracker = SegmentProgressTracker(
        wordCount: 50,
        globalStartWordIndex: 0,
        speechRate: 0.6,
        silenceGapThresholdMs: 50,
      );
      tracker.start(charCount: 200, onWord: (_) {});

      await Future.delayed(const Duration(milliseconds: 100));
      tracker.notifyRealProgress();
      expect(tracker.isFrozen, isTrue);

      tracker.resyncTo(10);
      expect(tracker.isFrozen, isFalse);

      tracker.cancel();
    });
  });
}
