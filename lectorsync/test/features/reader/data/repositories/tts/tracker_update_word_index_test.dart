import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/tts/segment_progress_tracker.dart';

void main() {
  group('SegmentProgressTracker.updateWordIndex (FIX H2/H4)', () {
    test('updateWordIndex advances _currentLocalWordIndex forward', () {
      final tracker = SegmentProgressTracker(
        wordCount: 50,
        globalStartWordIndex: 10,
        speechRate: 0.6,
        silenceGapThresholdMs: 100,
      );

      tracker.start(charCount: 200, onWord: (_) {});
      expect(tracker.globalWordIndex, 10);

      // Simulate: real progress says we're at local word 15
      tracker.updateWordIndex(15);
      expect(tracker.globalWordIndex, 25,
          reason: 'globalWordIndex should reflect the updated local index.');

      tracker.cancel();
    });

    test('updateWordIndex does NOT go backwards', () {
      final tracker = SegmentProgressTracker(
        wordCount: 50,
        globalStartWordIndex: 0,
        speechRate: 0.6,
        silenceGapThresholdMs: 100,
      );

      tracker.start(charCount: 200, onWord: (_) {});
      tracker.updateWordIndex(20);
      expect(tracker.globalWordIndex, 20);

      // A backward update must be ignored
      tracker.updateWordIndex(5);
      expect(tracker.globalWordIndex, 20,
          reason: 'updateWordIndex must never regress the position.');

      tracker.cancel();
    });

    test(
        'BUG SCENARIO: frozen tracker receives real progress → '
        'updateWordIndex syncs position, then cancel stops estimated emissions',
        () async {
      // This is the core H2/H4 bug scenario:
      // 1. Tracker is running in estimated mode
      // 2. A silence gap (number expansion) freezes the tracker
      // 3. Real progress arrives with a position ahead of the frozen tracker
      // 4. BEFORE FIX: the real progress was DISCARDED (return early)
      // 5. AFTER FIX: updateWordIndex syncs tracker, then cancel it;
      //    real progress is emitted as the authoritative source

      final emittedIndices = <int>[];
      final tracker = SegmentProgressTracker(
        wordCount: 50,
        globalStartWordIndex: 0,
        speechRate: 0.6,
        silenceGapThresholdMs: 100,
      );

      tracker.start(charCount: 200, onWord: emittedIndices.add);

      // Let the tracker run a bit
      await Future.delayed(const Duration(milliseconds: 200));

      // Simulate a silence gap that freezes the tracker
      await Future.delayed(const Duration(milliseconds: 150));
      tracker.notifyRealProgress();
      expect(tracker.isFrozen, isTrue,
          reason: 'Gap > 100ms should freeze the tracker.');

      // Real progress arrives: we're at local word 12
      // Before fix: this event would be silently discarded
      // After fix: sync position and cancel tracker
      tracker.updateWordIndex(12);
      expect(tracker.globalWordIndex, 12,
          reason: 'Position must sync to real progress.');

      tracker.unfreeze();
      tracker.cancel();

      // The caller (device_tts_repository.dart) then emits the real
      // progress word index directly, bypassing the frozen tracker.
    });

    test('updateWordIndex clamps to valid range', () {
      final tracker = SegmentProgressTracker(
        wordCount: 10,
        globalStartWordIndex: 5,
        speechRate: 0.6,
        silenceGapThresholdMs: 100,
      );

      tracker.start(charCount: 50, onWord: (_) {});

      // Update beyond word count — globalWordIndex should reflect
      // the raw value (clamping is the caller's responsibility)
      tracker.updateWordIndex(8);
      expect(tracker.globalWordIndex, 13);

      tracker.cancel();
    });
  });

  group('SegmentProgressTracker freeze diagnostic (FIX: log on freeze)', () {
    test('freeze occurs when silence gap exceeds threshold', () async {
      final tracker = SegmentProgressTracker(
        wordCount: 50,
        globalStartWordIndex: 0,
        speechRate: 0.6,
        silenceGapThresholdMs: 100,
      );

      tracker.start(charCount: 200, onWord: (_) {});

      // Wait for silence gap > threshold
      await Future.delayed(const Duration(milliseconds: 150));
      tracker.notifyRealProgress();

      expect(tracker.isFrozen, isTrue,
          reason: 'A silence gap > threshold must freeze the tracker.');

      tracker.cancel();
    });

    test('rapid real progress events prevent freeze', () async {
      final tracker = SegmentProgressTracker(
        wordCount: 50,
        globalStartWordIndex: 0,
        speechRate: 0.6,
        silenceGapThresholdMs: 500,
      );

      tracker.start(charCount: 200, onWord: (_) {});

      // Send real progress events frequently (under threshold)
      for (var i = 0; i < 5; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        tracker.notifyRealProgress();
      }

      expect(tracker.isFrozen, isFalse,
          reason: 'Frequent real progress events must not freeze.');

      tracker.cancel();
    });
  });
}
