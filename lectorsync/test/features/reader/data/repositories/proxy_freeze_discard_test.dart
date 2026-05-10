import 'package:flutter_test/flutter_test.dart';

/// Unit-level model of the proxy's status-flush gate.
///
/// The real `TtsRepositoryProxy` must NOT flush its pending word index
/// when the device has just signalled an interrupt-recovery (i.e. the
/// throttle is `_frozen`). Flushing in that state leaks an estimated
/// word index that is far ahead of where the engine actually is, which
/// produces the "se salta varios párrafos" jump on Web Speech overflow.
///
/// This test models that decision in isolation; the integration is
/// covered by the real proxy file (`tts_repository_proxy.dart`).
class _ProxyFlushGate {
  bool frozen = false;
  int pendingWordIdx = -1;
  int lastEmittedWordIdx = -1;
  final List<int> emitted = [];

  /// Mirrors the proxy's status-stream subscriber for terminal states.
  void onTerminalStatus() {
    if (frozen) {
      // FIX: discard pending — do NOT flush.
      pendingWordIdx = -1;
      return;
    }
    if (pendingWordIdx >= 0) {
      lastEmittedWordIdx = pendingWordIdx;
      emitted.add(pendingWordIdx);
      pendingWordIdx = -1;
    }
  }
}

void main() {
  group('Proxy frozen + terminal status (FIX: discard pending)', () {
    test('frozen=false → flushes pending on idle/error/completed '
        '(legacy behaviour preserved)', () {
      final gate = _ProxyFlushGate()..pendingWordIdx = 250;
      gate.onTerminalStatus();
      expect(gate.emitted, [250]);
      expect(gate.pendingWordIdx, -1);
      expect(gate.lastEmittedWordIdx, 250);
    });

    test('frozen=true → DROPS pending on terminal status — prevents the '
        'visible jump-forward when an interrupt cascades into idle', () {
      final gate = _ProxyFlushGate()
        ..frozen = true
        ..pendingWordIdx = 250
        ..lastEmittedWordIdx = 100;
      gate.onTerminalStatus();
      expect(gate.emitted, isEmpty,
          reason: 'A frozen throttle must not leak pending estimates.');
      expect(gate.pendingWordIdx, -1);
      expect(gate.lastEmittedWordIdx, 100,
          reason: 'lastEmittedWordIdx must NOT advance to the discarded '
              'pending value.');
    });

    test('frozen=true with no pending → no-op (no negative emissions)', () {
      final gate = _ProxyFlushGate()
        ..frozen = true
        ..pendingWordIdx = -1;
      gate.onTerminalStatus();
      expect(gate.emitted, isEmpty);
      expect(gate.pendingWordIdx, -1);
    });
  });
}
