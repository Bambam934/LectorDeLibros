import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/di/injection_container.dart' show TtsMode;
import '../../../../core/errors/failures.dart';
import '../../domain/repositories/tts_repository.dart';
import 'audio_tts_repository.dart';
import 'device_tts_repository.dart';

class TtsRepositoryProxy implements TtsRepository {
  TtsRepositoryProxy({
    required DeviceTtsRepository device,
    required AudioTtsRepository audio,
    required TtsMode initialMode,
  }) : _device = device, _audio = audio, _mode = initialMode {
    _wordCtrl = StreamController<int>.broadcast();
    _statusCtrl = StreamController<TtsPlaybackStatus>.broadcast();
    _attachSubscriptions(_activeRepo);
  }

  final DeviceTtsRepository _device;
  final AudioTtsRepository _audio;
  TtsMode _mode;

  late final StreamController<int> _wordCtrl;
  late final StreamController<TtsPlaybackStatus> _statusCtrl;
  StreamSubscription<int>? _wordSub;
  StreamSubscription<TtsPlaybackStatus>? _statusSub;
  StreamSubscription<void>? _recoverySub;

  static const _frameIntervalMs = 16;
  static const _catchUpThreshold = 50;

  /// FIX H3 — walking more than [_catchUpMaxSteps] words at 16 ms/word
  /// produces a visible multi-second fast-forward that the user perceives
  /// as "se salta varios párrafos". Beyond this limit we snap directly to
  /// the target instead of walking intermediate words.
  static const _catchUpMaxSteps = 30;

  Timer? _wordFrameTimer;
  int _pendingWordIdx = -1;
  int _lastEmittedWordIdx = -1;
  DateTime _lastWordEmit = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _catchUpTimer;
  int _catchUpTargetIdx = -1;

  /// FIX 35 — when the device repository signals an auto-recovery on its
  /// `recoveryStream`, freeze the throttle's pending word and suppress
  /// emissions until the next real progress event arrives. This avoids the
  /// visible "jump" of the highlight follower during the ~100-300ms gap
  /// between `interrupted` and `resumed` callbacks.
  bool _frozen = false;

  TtsRepository get _activeRepo =>
      _mode == TtsMode.device ? _device : _audio;

  @override
  Stream<int> get wordIndexStream => _wordCtrl.stream;

  @override
  Stream<TtsPlaybackStatus> get statusStream => _statusCtrl.stream;

  @override
  TtsPlaybackStatus get currentStatus => _activeRepo.currentStatus;

  void _attachSubscriptions(TtsRepository repo) {
    _wordSub?.cancel();
    _statusSub?.cancel();
    _recoverySub?.cancel();
    _recoverySub = null;
    _wordFrameTimer?.cancel();
    _catchUpTimer?.cancel();
    _pendingWordIdx = -1;
    _lastEmittedWordIdx = -1;
    _catchUpTargetIdx = -1;
    _frozen = false;

    // FIX 35 — only the device repository auto-recovers from engine
    // interrupts; the audio repository plays a server-rendered stream
    // and never produces an "interrupted" we'd want to mask.
    if (repo is DeviceTtsRepository) {
      _recoverySub = repo.recoveryStream.listen((_) {
        _frozen = true;
        _wordFrameTimer?.cancel();
        _wordFrameTimer = null;
        _pendingWordIdx = -1;
        _cancelCatchUp();
      });
    }

  _wordSub = repo.wordIndexStream.listen((idx) {
    if (_wordCtrl.isClosed) return;

    // FIX — debug assert for anomalous wordIndex deltas. A delta > 200
    // between consecutive events almost always means a tracker overshoot
    // or a stale-utterance leak. Catches the "se salta varios párrafos"
    // class of bugs early in development.
    final delta = idx - _lastEmittedWordIdx;
    if (_lastEmittedWordIdx >= 0) {
      assert(delta < 200, '[Proxy] anomalous wordIndex delta=$delta '
          'last=$_lastEmittedWordIdx new=$idx');
    }

    // FIX 35 — first real progress event from the recovered segment
    // unfreezes the throttle. The catch-up rewrite below still applies.
    if (_frozen) {
      _frozen = false;
    }

    _cancelCatchUp();

    if (_lastEmittedWordIdx >= 0 && delta > _catchUpThreshold) {
        // FIX H3 — if the gap is too large, walking every intermediate
        // word at 16 ms produces a visible fast-forward lasting several
        // seconds. Snap directly to the target so the highlight
        // follower catches up in a single frame instead of "walking"
        // through multiple paragraphs.
        if (delta > _catchUpMaxSteps) {
          _lastEmittedWordIdx = idx;
          _pendingWordIdx = idx;
          _lastWordEmit = DateTime.now();
          _wordCtrl.add(idx);
          _pendingWordIdx = -1;
          return;
        }
        _startCatchUp(idx);
        return;
      }

      _pendingWordIdx = idx;

      final now = DateTime.now();
      final elapsed = now.difference(_lastWordEmit).inMilliseconds;
      if (elapsed >= _frameIntervalMs) {
        _lastWordEmit = now;
        _lastEmittedWordIdx = idx;
        _wordCtrl.add(_pendingWordIdx);
        _pendingWordIdx = -1;
        _wordFrameTimer?.cancel();
        _wordFrameTimer = null;
      } else {
        _wordFrameTimer ??= Timer(
          Duration(milliseconds: _frameIntervalMs - elapsed),
          () {
            _wordFrameTimer = null;
            if (!_wordCtrl.isClosed && _pendingWordIdx >= 0) {
              _lastWordEmit = DateTime.now();
              _lastEmittedWordIdx = _pendingWordIdx;
              _wordCtrl.add(_pendingWordIdx);
              _pendingWordIdx = -1;
            }
          },
        );
      }
    });

    _statusSub = repo.statusStream.listen((s) {
      if (_statusCtrl.isClosed) return;
      if (s == TtsPlaybackStatus.idle ||
          s == TtsPlaybackStatus.completed ||
          s == TtsPlaybackStatus.error) {
        _wordFrameTimer?.cancel();
        _wordFrameTimer = null;
        _cancelCatchUp();
        // FIX (defensive) — if the throttle is frozen because the
        // device just signalled an interrupt-recovery, the pending
        // word index is from a stale (over-shooting) estimated tracker
        // and must NOT be flushed. Discarding it here prevents the
        // visible jump of "se salta varios párrafos" when an
        // utterance overflows on Web Speech.
        if (_frozen) {
          _pendingWordIdx = -1;
        } else if (_pendingWordIdx >= 0 && !_wordCtrl.isClosed) {
          _lastEmittedWordIdx = _pendingWordIdx;
          _wordCtrl.add(_pendingWordIdx);
          _pendingWordIdx = -1;
        }
      }
      _statusCtrl.add(s);
    });
  }

  void _startCatchUp(int targetIdx) {
    _catchUpTargetIdx = targetIdx;
    var current = _lastEmittedWordIdx + 1;

    void emitNext() {
      if (_wordCtrl.isClosed || current > _catchUpTargetIdx) {
        _catchUpTimer?.cancel();
        _catchUpTimer = null;
        return;
      }
      _lastEmittedWordIdx = current;
      _wordCtrl.add(current);
      current++;
      if (current > _catchUpTargetIdx) {
        _catchUpTimer?.cancel();
        _catchUpTimer = null;
        return;
      }
      _catchUpTimer = Timer(
        Duration(milliseconds: _frameIntervalMs),
        emitNext,
      );
    }

    emitNext();
  }

  void _cancelCatchUp() {
    _catchUpTimer?.cancel();
    _catchUpTimer = null;
    _catchUpTargetIdx = -1;
  }

  Future<void> switchMode(TtsMode newMode, {String? voiceId}) async {
    final modeChanged = _mode != newMode;
    if (!modeChanged && voiceId == null) return;

    await _activeRepo.stop();

    if (modeChanged) {
      _mode = newMode;
      _attachSubscriptions(_activeRepo);
    }

    if (voiceId != null) {
      _audio.setVoiceId(voiceId);
    }
  }

  @override
  Future<Either<Failure, Unit>> initialize() => _activeRepo.initialize();

  @override
  Future<Either<Failure, Unit>> speak({
    required String text,
    required List<String> words,
    int startWordIndex = 0,
  }) =>
      _activeRepo.speak(text: text, words: words, startWordIndex: startWordIndex);

  @override
  Future<Either<Failure, Unit>> stop() => _activeRepo.stop();

  @override
  Future<Either<Failure, Unit>> setLanguage(String languageCode) =>
      _activeRepo.setLanguage(languageCode);

  @override
  Future<void> dispose() async {
    _wordFrameTimer?.cancel();
    _catchUpTimer?.cancel();
    _wordSub?.cancel();
    _statusSub?.cancel();
    _recoverySub?.cancel();
    await _wordCtrl.close();
    await _statusCtrl.close();
  }
}
