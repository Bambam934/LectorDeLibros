import 'package:flutter_test/flutter_test.dart';

/// Unit-level model of the proxy's catch-up + snap decision.
///
/// FIX H3 — when the delta between consecutive word indices exceeds
/// [_catchUpThreshold], the proxy must decide between WALKING every
/// intermediate word at 16ms/word (visible fast-forward) or SNAPPING
/// directly to the target.
///
/// Since [_catchUpMaxSteps] (30) < [_catchUpThreshold] (50), any delta
/// that triggers catch-up ALSO exceeds the max-step limit, so ALL
/// catch-ups snap. This is intentional: walking is only useful for
/// very small catch-ups, and those don't exceed the threshold anyway.
const _catchUpThreshold = 50;
const _catchUpMaxSteps = 30;

class _ProxyCatchUp {
  int lastEmitted = -1;
  final List<int> emitted = [];

  void onWordIndex(int idx) {
    final delta = lastEmitted >= 0 ? idx - lastEmitted : 0;

    if (lastEmitted < 0) {
      emitted.add(idx);
      lastEmitted = idx;
      return;
    }

    if (delta > _catchUpThreshold) {
      if (delta > _catchUpMaxSteps) {
        // SNAP — emit target directly, skip intermediates.
        emitted.add(idx);
        lastEmitted = idx;
      } else {
        // WALK — emit every intermediate word.
        // NOTE: with current constants this path is unreachable since
        // maxSteps < threshold, but the logic is preserved for future
        // tuning (e.g. if maxSteps is raised above threshold).
        for (var i = lastEmitted + 1; i <= idx; i++) {
          emitted.add(i);
        }
        lastEmitted = idx;
      }
    } else {
      emitted.add(idx);
      lastEmitted = idx;
    }
  }
}

void main() {
  group('Proxy catch-up max steps (FIX H3: snap beyond limit)', () {
    test('delta below threshold emits directly (no catch-up)', () {
      final proxy = _ProxyCatchUp();
      proxy.onWordIndex(0);
      proxy.onWordIndex(1);
      proxy.onWordIndex(49);
      expect(proxy.emitted, [0, 1, 49]);
    });

    test('delta at threshold emits directly (boundary)', () {
      final proxy = _ProxyCatchUp();
      proxy.onWordIndex(0);
      proxy.onWordIndex(50);
      expect(proxy.emitted, [0, 50]);
    });

    test('delta just above threshold SNAPS (maxSteps < threshold)', () {
      final proxy = _ProxyCatchUp();
      proxy.onWordIndex(0);
      proxy.onWordIndex(51);
      // delta=51 > threshold=50 AND delta=51 > maxSteps=30 → snap
      expect(proxy.emitted, [0, 51],
          reason: 'Since _catchUpMaxSteps < _catchUpThreshold, any delta '
              'that triggers catch-up also exceeds maxSteps → snap.');
    });

    test('large delta SNAPS — prevents visible fast-forward', () {
      final proxy = _ProxyCatchUp();
      proxy.onWordIndex(0);
      proxy.onWordIndex(100);
      // delta=100 > maxSteps=30 → snap: only 2 emissions total
      expect(proxy.emitted, [0, 100],
          reason: 'A delta of 100 must snap directly to target, not walk '
              '100 words at 16ms/word (1.6s visible fast-forward).');
      expect(proxy.lastEmitted, 100);
    });

    test('rapid large jumps each snap independently', () {
      final proxy = _ProxyCatchUp();
      proxy.onWordIndex(0);
      proxy.onWordIndex(80);
      proxy.onWordIndex(200);
      expect(proxy.emitted, [0, 80, 200],
          reason: 'Each large delta snaps independently without walking.');
    });

    test('first emission never triggers catch-up regardless of value', () {
      final proxy = _ProxyCatchUp();
      proxy.onWordIndex(500);
      expect(proxy.emitted, [500]);
    });

    test(
        'BUG SCENARIO: "28 de Abril de 1967" — number expansion causes '
        'tracker overshoot delta > maxSteps → snap prevents paragraph jump',
        () {
      // Simulates: tracker at word 45, real progress arrives at word 120
      // after the TTS engine finishes expanding "mil novecientos sesenta y
      // siete" (4x expansion). Without the snap, the proxy would walk
      // 75 words at 16ms = 1.2s visible fast-forward across paragraphs.
      final proxy = _ProxyCatchUp();
      proxy.onWordIndex(45);
      proxy.onWordIndex(120);
      // delta=75 > maxSteps=30 → snap
      expect(proxy.emitted, [45, 120],
          reason: 'Overshoot from number expansion must snap, not walk.');
    });

    test('walk path is reachable if maxSteps > threshold (future tuning)',
        () {
      // This test demonstrates the walk path works correctly if constants
      // are adjusted so maxSteps > threshold (e.g. threshold=50, maxSteps=80).
      // With those values, a delta of 60 would walk but a delta of 100
      // would snap.
      const threshold = 50;
      const maxSteps = 80;
      int lastEmitted = 0;
      final emitted = <int>[];

      void onWordIndex(int idx) {
        final delta = idx - lastEmitted;
        if (delta > threshold) {
          if (delta > maxSteps) {
            emitted.add(idx);
            lastEmitted = idx;
          } else {
            for (var i = lastEmitted + 1; i <= idx; i++) {
              emitted.add(i);
            }
            lastEmitted = idx;
          }
        } else {
          emitted.add(idx);
          lastEmitted = idx;
        }
      }

      // delta=60: above threshold=50 but below maxSteps=80 → walk
      onWordIndex(60);
      expect(emitted.length, 60,
          reason: 'Walk emits 60 intermediate indices (1..60).');
      expect(emitted.last, 60);

      emitted.clear();
      lastEmitted = 60;

      // delta=100: above maxSteps=80 → snap
      onWordIndex(160);
      expect(emitted, [160],
          reason: 'Snap emits only the target index.');
    });
  });
}
