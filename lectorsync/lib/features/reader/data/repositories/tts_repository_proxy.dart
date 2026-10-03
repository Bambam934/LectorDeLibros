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
  /// Delta a partir del cual un salto deja de tratarse como progreso normal.
  /// Por debajo basta con el acelerador de 16 ms.
  static const _catchUpThreshold = 50;

  /// FIX H3 — walking more than [_catchUpMaxSteps] words at 16 ms/word
  /// produces a visible multi-second fast-forward that the user perceives
  /// as "se salta varios párrafos". Beyond this limit we snap directly to
  /// the target instead of walking intermediate words.
  ///
  /// **`_catchUpMaxSteps` (30) es MENOR que `_catchUpThreshold` (50) a
  /// propósito, y por eso `_startCatchUp` no llega a ejecutarse nunca.** Todo
  /// delta que activa el catch-up supera también este límite, así que siempre
  /// se hace snap. No es un descuido: caminar solo compensa en saltos
  /// pequeños, y esos ni siquiera cruzan el umbral. El código del paseo se
  /// conserva por si algún día se quiere afinar la horquilla —subiendo
  /// `_catchUpMaxSteps` POR ENCIMA del umbral—, y
  /// `proxy_catch_up_max_steps_test.dart` fija los dos comportamientos.
  ///
  /// Si vienes a "arreglar" esta relación entre constantes: activar el paseo
  /// es un cambio de producto sobre el seguidor de palabras, con su propio
  /// riesgo, no una corrección.
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

    final delta = idx - _lastEmittedWordIdx;
    // Un delta grande = reposicionamiento del usuario (slider, marcador, botón
    // "volver a la lectura"), NO un salto espurio del tracker. Antes esto era
    // `assert(delta < 200)` que LANZABA en bucle: la excepción cortaba el
    // listener antes de actualizar `_lastEmittedWordIdx` (abajo), que quedaba
    // congelado y cada palabra siguiente volvía a fallar con delta creciente.
    // La lógica de snap de más abajo ya maneja los saltos grandes; aquí solo
    // dejamos rastro en debug, sin romper el flujo.
    assert(() {
      if (_lastEmittedWordIdx >= 0 && delta.abs() >= 200) {
        debugPrint('[Proxy] salto grande de wordIndex delta=$delta '
            'last=$_lastEmittedWordIdx new=$idx (reposicionamiento)');
      }
      return true;
    }());

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
