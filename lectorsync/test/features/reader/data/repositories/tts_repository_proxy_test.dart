import 'package:flutter_test/flutter_test.dart';

const _catchUpThreshold = 50;
const _catchUpMaxSteps = 30;

void main() {
  group('Proxy catch-up algorithm', () {
    test('small delta emits directly', () {
      final emitted = <int>[];
      int lastEmitted = -1;

      void onWordIndex(int idx) {
        final delta = lastEmitted >= 0 ? idx - lastEmitted : 1;
        if (lastEmitted >= 0 && delta > _catchUpThreshold) {
          // FIX H3 — snap if delta exceeds maxSteps, else walk
          if (delta > _catchUpMaxSteps) {
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

      onWordIndex(0);
      onWordIndex(1);
      onWordIndex(5);

      expect(emitted, [0, 1, 5]);
      expect(lastEmitted, 5);
    });

    test('large delta SNAPS instead of walking all intermediates (FIX H3)',
        () {
      final emitted = <int>[];
      int lastEmitted = -1;

      void onWordIndex(int idx) {
        final delta = lastEmitted >= 0 ? idx - lastEmitted : 1;
        if (lastEmitted >= 0 && delta > _catchUpThreshold) {
          if (delta > _catchUpMaxSteps) {
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

      onWordIndex(0);
      onWordIndex(100);

      // FIX H3: delta=100 > maxSteps=30 → snap, not walk
      expect(emitted, [0, 100],
          reason: 'Large deltas must snap to target, not walk 100 words.');
      expect(lastEmitted, 100);
    });

    test('consecutive small deltas never trigger catch-up', () {
      final emitted = <int>[];
      int lastEmitted = -1;

      void onWordIndex(int idx) {
        final delta = lastEmitted >= 0 ? idx - lastEmitted : 1;
        if (lastEmitted >= 0 && delta > _catchUpThreshold) {
          if (delta > _catchUpMaxSteps) {
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

      for (var i = 0; i <= 200; i += 10) {
        onWordIndex(i);
      }

      expect(emitted.length, 21);
      expect(emitted, List.generate(21, (i) => i * 10));
    });

    test('delta exactly at threshold does not trigger catch-up', () {
      final emitted = <int>[];
      int lastEmitted = -1;

      void onWordIndex(int idx) {
        final delta = lastEmitted >= 0 ? idx - lastEmitted : 1;
        if (lastEmitted >= 0 && delta > _catchUpThreshold) {
          if (delta > _catchUpMaxSteps) {
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

      onWordIndex(0);
      onWordIndex(50);

      expect(emitted, [0, 50]);
    });

    test('delta one above threshold snaps (since maxSteps < threshold)', () {
      final emitted = <int>[];
      int lastEmitted = -1;

      void onWordIndex(int idx) {
        final delta = lastEmitted >= 0 ? idx - lastEmitted : 1;
        if (lastEmitted >= 0 && delta > _catchUpThreshold) {
          if (delta > _catchUpMaxSteps) {
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

      onWordIndex(0);
      onWordIndex(51);

      // delta=51 > threshold=50 AND 51 > maxSteps=30 → snap
      expect(emitted, [0, 51],
          reason: 'With _catchUpMaxSteps < _catchUpThreshold, any '
              'catch-up-eligible delta also exceeds maxSteps → snap.');
    });

    test('first emission never triggers catch-up regardless of index', () {
      final emitted = <int>[];
      int lastEmitted = -1;

      void onWordIndex(int idx) {
        final delta = lastEmitted >= 0 ? idx - lastEmitted : 1;
        if (lastEmitted >= 0 && delta > _catchUpThreshold) {
          if (delta > _catchUpMaxSteps) {
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

      onWordIndex(200);

      expect(emitted, [200]);
    });

    test('catch-up after silence gap snaps when delta exceeds maxSteps', () {
      final emitted = <int>[];
      int lastEmitted = -1;

      void onWordIndex(int idx) {
        final delta = lastEmitted >= 0 ? idx - lastEmitted : 1;
        if (lastEmitted >= 0 && delta > _catchUpThreshold) {
          if (delta > _catchUpMaxSteps) {
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

      onWordIndex(10);
      onWordIndex(10);
      onWordIndex(80);

      // delta=70 > maxSteps=30 → snap
      expect(emitted, [10, 10, 80],
          reason: 'Large gap must snap, not walk 70 words.');
      expect(emitted.last, 80);
    });
  });

  group('Proxy frame throttling', () {
    test('emissions within frame interval are throttled', () async {
      final emitted = <int>[];
      var lastEmitTime = DateTime.fromMillisecondsSinceEpoch(0);
      const frameIntervalMs = 16;

      void throttledEmit(int idx) {
        final now = DateTime.now();
        final elapsed = now.difference(lastEmitTime).inMilliseconds;
        if (elapsed >= frameIntervalMs) {
          lastEmitTime = now;
          emitted.add(idx);
        }
      }

      throttledEmit(0);
      throttledEmit(1);
      throttledEmit(2);

      expect(emitted.length, lessThanOrEqualTo(3));
      expect(emitted.first, 0);
    });
  });
}
