import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/repositories/tts_repository.dart';
import 'tts/native_mobile_tts_adapter.dart';
import 'tts/segment_progress_tracker.dart';
import 'tts/tts_adapter.dart';
import 'tts/tts_capabilities.dart';
import 'tts/web_tts_adapter.dart';

class DeviceTtsRepository implements TtsRepository {
  DeviceTtsRepository() : _adapter = _createAdapter();

  static TtsAdapter _createAdapter() {
    if (kIsWeb) return WebTtsAdapter();
    return NativeMobileTtsAdapter();
  }

  final TtsAdapter _adapter;

  bool _isInitialized = false;
  bool _initFailed = false;
  bool _platformSupported = true;

  final StreamController<int> _wordIndexController =
      StreamController<int>.broadcast();
  final StreamController<TtsPlaybackStatus> _statusController =
      StreamController<TtsPlaybackStatus>.broadcast();
  final StreamController<bool> _estimatingController =
      StreamController<bool>.broadcast();
  final StreamController<void> _recoveryController =
      StreamController<void>.broadcast();

  TtsPlaybackStatus _currentStatus = TtsPlaybackStatus.idle;

  List<int> _charOffsets = [];
  int _startOffset = 0;

  List<SpeakSegment> _pendingSegments = [];
  int _currentSegmentIndex = 0;
  bool _isSegmentSpeaking = false;
  static const int _maxWordsPerSegment = 200;

  SegmentProgressTracker? _segmentTracker;
  double? _calibratedMsPerChar;

  bool _useEstimatedProgress = false;
  Timer? _progressDetectionTimer;
  bool _receivedRealProgress = false;
  static const Duration _progressDetectionWindow =
      Duration(milliseconds: 300);

  Completer<void>? _segmentCompletionCompleter;
  bool _stopRequested = false;
  int _speakGeneration = 0;
  Completer<void>? _engineReadyCompleter;

  /// True iff stop()/setSpeechRate()/setVoice() (or any user-driven mutator
  /// that internally calls _adapter.stop()) is the cause of any incoming
  /// "interrupted" error. Used by the error handler to distinguish a genuine
  /// browser-side overflow interrupt from a user-requested stop.
  bool _userRequestedStop = false;

  /// FIX 33 — auto-recovery state. When the underlying TTS fires an
  /// `"interrupted"` error not caused by the user, we re-encode the
  /// current segment from the last known word, without bumping
  /// `_speakGeneration` (which would cause the proxy to flush its
  /// pending word index and produce a visual jump).
  bool _recoveryPending = false;
  int _segmentRetryCount = 0;
  static const int _maxSegmentRetries = 2;

  /// Local word index inside the current segment, last reported by either
  /// the real progress handler or the estimated tracker. Used to slice
  /// the segment text on auto-recovery so playback resumes near the
  /// interrupt point instead of restarting the segment.
  int _lastKnownLocalWordIdx = 0;

  /// The segment description currently being spoken. Equal to
  /// `_pendingSegments[_currentSegmentIndex]` for normal playback and
  /// to a sliced view of it during a recovery attempt. Used by the
  /// fallback estimated-tracker initialisation path so the tracker
  /// doesn't desync after a recovery slice.
  SpeakSegment? _currentEffectiveSegment;

  double _speechRate = 0.6;

  double get speechRate => _speechRate;

  set speechRate(double value) {
    _speechRate = value.clamp(0.0, 1.0);
    if (_isInitialized && _platformSupported) {
      // FIX 34 — setSpeechRate may internally cancel the active utterance;
      // mark the resulting interrupt as user-driven so we don't auto-retry
      // a segment the user just rate-changed.
      _userRequestedStop = true;
      _adapter.setSpeechRate(_speechRate);
      // Reset shortly after; the engine fires the cancel callback async.
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        _userRequestedStop = false;
      });
    }
    if (_segmentTracker?.isRunning == true) {
      _restartSegmentTracker();
    }
  }

  Map<String, String>? _selectedVoice;

  Map<String, String>? get selectedVoice => _selectedVoice;

  TtsCapabilities get capabilities => _adapter.capabilities;

  bool get isEstimatingProgress {
    final adapter = _adapter;
    if (adapter is WebTtsAdapter) {
      return adapter.isEstimatingProgress;
    }
    return _useEstimatedProgress;
  }

  Stream<bool> get estimatingStream => _estimatingController.stream;

  /// Emits a unit each time the repository starts an auto-recovery for
  /// a segment that was interrupted by the underlying engine (e.g.
  /// Web Speech firing `SpeechSynthesisErrorEvent("interrupted")` due
  /// to utterance-length overflow). Listeners (notably the
  /// `TtsRepositoryProxy` throttle) should freeze any pending word
  /// emissions until the next real progress event.
  Stream<void> get recoveryStream => _recoveryController.stream;

  Future<List<Map<String, String>>> getAvailableVoices({
    String? localePrefix,
  }) async {
    if (!_platformSupported) return const [];
    if (!_isInitialized) {
      final init = await initialize();
      if (init.isLeft()) return const [];
    }
    return _adapter.getVoices(localePrefix: localePrefix);
  }

  Future<void> setVoice(Map<String, String> voice) async {
    if (!_platformSupported) return;
    if (!_isInitialized) {
      final init = await initialize();
      if (init.isLeft()) return;
    }
    // FIX 34 — setVoice can synchronously trigger an internal stop on the
    // engine; mark the upcoming "interrupted" error as user-driven so the
    // recovery handler does NOT auto-retry.
    final wasFlag = _userRequestedStop;
    _userRequestedStop = true;
    try {
      await _adapter.setVoice(voice);
      _selectedVoice = Map<String, String>.from(voice);
      debugPrint(
          '[DeviceTTS] setVoice ok: ${voice['name']} (${voice['locale']})');
    } catch (e) {
      debugPrint('[DeviceTTS] setVoice error: $e');
    } finally {
      _userRequestedStop = wasFlag;
    }
  }

  @override
  Stream<int> get wordIndexStream => _wordIndexController.stream;

  @override
  Stream<TtsPlaybackStatus> get statusStream => _statusController.stream;

  @override
  TtsPlaybackStatus get currentStatus => _currentStatus;

  @override
  Future<Either<Failure, Unit>> initialize() async {
    if (_isInitialized && !_initFailed) return right(unit);

    if (!_isPlatformSupported()) {
      _platformSupported = false;
      _isInitialized = true;
      return right(unit);
    }

    try {
      _engineReadyCompleter = Completer<void>();

      final tts = _adapter.tts;

      tts.setStartHandler(() {
        debugPrint('[DeviceTTS] startHandler fired');
        if (_engineReadyCompleter != null &&
            !_engineReadyCompleter!.isCompleted) {
          _engineReadyCompleter!.complete();
        }
        if (_isSegmentSpeaking) {
          _emit(TtsPlaybackStatus.playing);
        }
      });

      await tts.awaitSpeakCompletion(true);

      await _adapter.initialize(_speechRate);

      tts.setCompletionHandler(() {
        debugPrint('[DeviceTTS] completionHandler fired '
            'speaking=$_isSegmentSpeaking gen=$_speakGeneration');
        if (!_isSegmentSpeaking) return;
        _completeSegment();
      });
      tts.setCancelHandler(() {
        debugPrint('[DeviceTTS] cancel callback: '
            'speaking=$_isSegmentSpeaking gen=$_speakGeneration');
        if (!_isSegmentSpeaking) {
          _emit(TtsPlaybackStatus.idle);
        }
      });
      tts.setErrorHandler((msg) {
        debugPrint('[DeviceTTS] error callback: $msg | '
            'speaking=$_isSegmentSpeaking gen=$_speakGeneration '
            'localWord=$_lastKnownLocalWordIdx '
            'segStart=$_startOffset retries=$_segmentRetryCount '
            'userStop=$_userRequestedStop');

        final isInterrupted = DeviceTtsRepository._isInterruptedMessage(msg);

        // FIX (defensive) — Always cancel the in-flight segment tracker
        // on any error so it cannot keep emitting estimated word indices
        // past the interrupt point. Without this, an `error` for an
        // already-stale utterance leaves the timer-based tracker
        // running and the highlight fast-forwards via the proxy's
        // catch-up logic.
        _segmentTracker?.cancel();
        _segmentTracker = null;

        // FIX (defensive) — Always freeze the proxy throttle on
        // interrupt-class errors, regardless of speaking/gen state.
        // The proxy clears its pending word index on freeze, so when
        // the BLoC later receives `error`/`idle` status the proxy's
        // status flush no longer leaks an estimated-but-unrealized
        // word index that would jump the highlight forward.
        if (isInterrupted && !_recoveryController.isClosed) {
          _recoveryController.add(null);
        }

        if (!_isSegmentSpeaking) {
          debugPrint('[DeviceTTS] error: not speaking — '
              'tracker+throttle cleared, no recovery attempted '
              '(stale utterance or post-stop error)');
          return;
        }

        // FIX 33 — Auto-recovery for "interrupted" errors that the user
        // did NOT cause. Web Speech fires this when an utterance exceeds
        // its empirical char limit (~200 in Chrome). We re-encode the
        // current segment from the last known word without bumping
        // _speakGeneration (so the proxy does NOT flush its pending word).
        final shouldRecover = DeviceTtsRepository.shouldAutoRecover(
          errorMessage: msg,
          userRequestedStop: _userRequestedStop,
          retryCount: _segmentRetryCount,
        );

        if (shouldRecover) {
          _segmentRetryCount++;
          _recoveryPending = true;
          debugPrint('[DeviceTTS] auto-recovery: re-speak '
              'seg=$_currentSegmentIndex from word=$_lastKnownLocalWordIdx '
              '(global=${_startOffset + _lastKnownLocalWordIdx}) '
              'retry=$_segmentRetryCount/$_maxSegmentRetries');
          // Unblock the speak loop so it can re-enter with recovery state.
          if (_segmentCompletionCompleter != null &&
              !_segmentCompletionCompleter!.isCompleted) {
            _segmentCompletionCompleter!.complete();
          }
          return;
        }

        _stopRequested = true;
        _cancelSegmentQueue();
        _cancelEstimatedProgress();
        _emit(TtsPlaybackStatus.error);
      });

      tts.setProgressHandler((text, start, end, word) {
        if (_charOffsets.isEmpty) return;

        final adapter = _adapter;
        if (adapter is WebTtsAdapter) {
          adapter.onRealProgressEvent();
          if (adapter.isEstimatingProgress) return;
        }

        _receivedRealProgress = true;
        _cancelEstimatedProgress();
        _useEstimatedProgress = false;
        _emitEstimating(false);

        if (_segmentTracker != null && _segmentTracker!.isRunning) {
          _segmentTracker!.notifyRealProgress();
          if (_segmentTracker!.isFrozen) {
            // FIX H2/H4 — when the tracker is frozen due to a silence
            // gap (e.g. during long number expansion), we MUST still
            // emit this real progress word index instead of returning
            // early. Sync the tracker's internal position so it
            // resumes from the real position rather than a stale
            // estimate, then cancel it: the real progress stream is
            // now the authoritative source.
            final localIdx = _binarySearch(_charOffsets, start);
            _segmentTracker!.updateWordIndex(localIdx);
            _segmentTracker!.unfreeze();
            _segmentTracker!.cancel();
            _segmentTracker = null;
            // Fall through to emit the real progress word index below.
          } else {
            _segmentTracker!.cancel();
          }
        }

        final localIdx = _binarySearch(_charOffsets, start);
        _lastKnownLocalWordIdx = localIdx;
        final globalIdx = _startOffset + localIdx;
        if (!_wordIndexController.isClosed) {
          _wordIndexController.add(globalIdx);
        }
      });

      if (_adapter.capabilities.needsSpeakProbe) {
        try {
          await tts.speak('').timeout(const Duration(seconds: 5));
        } catch (_) {}
        if (_engineReadyCompleter != null &&
            !_engineReadyCompleter!.isCompleted) {
          await _engineReadyCompleter!.future
              .timeout(const Duration(seconds: 5), onTimeout: () {
            debugPrint(
                '[DeviceTTS] engine init timed out — proceeding anyway');
          });
        }
        await tts.stop();
      }

      _isInitialized = true;
      _initFailed = false;
      debugPrint('[DeviceTTS] initialization complete '
          '(adapter: ${kIsWeb ? 'Web' : 'NativeMobile'})');
      return right(unit);
    } catch (e) {
      debugPrint('[DeviceTTS] init error: $e');
      _isInitialized = true;
      _initFailed = true;
      _platformSupported = false;
      return right(unit);
    }
  }

  @override
  Future<Either<Failure, Unit>> speak({
    required String text,
    required List<String> words,
    int startWordIndex = 0,
  }) async {
    if (!_isInitialized) {
      final init = await initialize();
      if (init.isLeft()) return init;
    }

    if (!_platformSupported) return right(unit);

    try {
      final wasSpeaking = _isSegmentSpeaking;
      _stopRequested = true;
      _cancelSegmentQueue();
      _cancelEstimatedProgress();
      _progressDetectionTimer?.cancel();
      _progressDetectionTimer = null;

      debugPrint('[DeviceTTS] speak: words=${words.length} '
          'startIdx=$startWordIndex wasSpeaking=$wasSpeaking');

      if (_platformSupported && wasSpeaking) {
        // FIX 34 — internal stop driven by a new speak() call; treat as
        // user-driven so we don't try to "recover" the segment we just
        // intentionally aborted.
        _userRequestedStop = true;
        try {
          await _adapter
              .stop()
              .timeout(const Duration(milliseconds: 600));
        } catch (_) {}
        _userRequestedStop = false;
      }

      _speakGeneration++;
      debugPrint('[DeviceTTS] gen++ (speak) → $_speakGeneration');
      _segmentRetryCount = 0;
      _recoveryPending = false;
      _lastKnownLocalWordIdx = 0;

      final clampedStart =
          startWordIndex.clamp(0, words.isEmpty ? 0 : words.length - 1);

      final speakWords =
          clampedStart > 0 ? words.sublist(clampedStart) : words;
      final speakText = _buildSpeakText(text, words, clampedStart);

      // FIX 32 — split by word count first, then enforce per-utterance
      // char cap (FIX 31). On Web this prevents Chrome from silently
      // firing "interrupted" once the utterance exceeds ~200 chars.
      _pendingSegments = enforceMaxSegmentLength(
        splitIntoSegments(speakText, speakWords, clampedStart),
        _adapter.capabilities.maxUtteranceChars,
      );
      _currentSegmentIndex = 0;
      _isSegmentSpeaking = true;
      _stopRequested = false;
      _receivedRealProgress = false;

      final adapter = _adapter;
      if (adapter is WebTtsAdapter && adapter.isEstimatingProgress) {
        _useEstimatedProgress = true;
        _emitEstimating(true);
      } else {
        _useEstimatedProgress = false;
      }

      _emit(TtsPlaybackStatus.loading);
      _speakSegmentLoop(_speakGeneration);

      return right(unit);
    } catch (e) {
      _emit(TtsPlaybackStatus.error);
      return left(ServerFailure('TTS speak error: $e'));
    }
  }

  Future<void> _speakSegmentLoop(int generation) async {
    const maxRetries = 2;
    const completionBufferMs = 50;

    while (_currentSegmentIndex < _pendingSegments.length &&
        !_stopRequested &&
        generation == _speakGeneration) {
      await Future.microtask(() {});

      _segmentTracker?.cancel();
      _segmentTracker = null;

      if (_stopRequested || generation != _speakGeneration) break;

      final segment = _pendingSegments[_currentSegmentIndex];

      // FIX 33 — auto-recovery slice. If the previous attempt for this
      // segment was interrupted by the engine, resume from the last word
      // we observed playing instead of restarting the segment.
      String textToSpeak;
      List<String> effectiveWords;
      int effectiveStartWord;
      final bool isRecoveryAttempt = _recoveryPending;
      if (isRecoveryAttempt) {
        _recoveryPending = false;
        final rawStart = _lastKnownLocalWordIdx;
        // Resume from the very next word; if we have not received any
        // progress yet (rawStart == 0 with retry count > 0), re-speak
        // the whole segment.
        final localStart = rawStart > 0
            ? rawStart.clamp(0, segment.words.length)
            : 0;
        if (localStart >= segment.words.length) {
          // The interrupt happened essentially at end-of-segment. Treat
          // as a normal completion and advance.
          debugPrint('[DeviceTTS] recovery: segment already past last word, '
              'advancing seg=$_currentSegmentIndex');
          _currentSegmentIndex++;
          _segmentRetryCount = 0;
          continue;
        }
        effectiveWords = segment.words.sublist(localStart);
        textToSpeak = effectiveWords.join(' ');
        effectiveStartWord = segment.globalStartWordIndex + localStart;
        debugPrint('[DeviceTTS] recovery slice: seg=$_currentSegmentIndex '
            'localStart=$localStart effChars=${textToSpeak.length} '
            'effWords=${effectiveWords.length}');
      } else {
        // New segment — reset retry counter for next interruption window.
        _segmentRetryCount = 0;
        effectiveWords = segment.words;
        textToSpeak = segment.text.isEmpty ? '...' : segment.text;
        effectiveStartWord = segment.globalStartWordIndex;
      }

      _startOffset = effectiveStartWord;
      _charOffsets = _buildCharOffsets(textToSpeak, effectiveWords);
      _receivedRealProgress = false;
      _lastKnownLocalWordIdx = 0;

      // FIX 36 — log chars vs adapter cap; warn if a segment somehow still
      // exceeds the limit (defensive — _enforceMaxSegmentLength should
      // have already split it).
      final maxChars = _adapter.capabilities.maxUtteranceChars;
      if (textToSpeak.length > maxChars) {
        debugPrint('[DeviceTTS] WARN: segment exceeds adapter limit '
            '(${textToSpeak.length} > $maxChars), will be sub-split');
      }
      debugPrint('[DeviceTTS] _speakSegment: '
          'seg=$_currentSegmentIndex/${_pendingSegments.length} '
          'chars=${textToSpeak.length}/$maxChars gen=$generation '
          '${isRecoveryAttempt ? 'RECOVERY ' : ''}'
          'retries=$_segmentRetryCount');
      _emit(TtsPlaybackStatus.playing);

      _segmentCompletionCompleter = Completer<void>();

      // FIX — when we're in a recovery slice, the tracker must use the
      // SLICED word range, not the original segment. Otherwise the
      // tracker emits global indices starting from the original
      // segment.globalStartWordIndex, which can land BEHIND the
      // already-emitted highlight (visible jump backwards) or, after
      // catch-up, JUMP FORWARD several words at once.
      final trackerSegment = isRecoveryAttempt
          ? SpeakSegment(
              text: textToSpeak,
              words: effectiveWords,
              globalStartWordIndex: effectiveStartWord,
              audibleCharCount: computeAudibleCharCount(textToSpeak),
              hasNumbers: detectNumbers(textToSpeak),
            )
          : segment;
      _currentEffectiveSegment = trackerSegment;

      if (_useEstimatedProgress) {
        _startSegmentTracker(trackerSegment);
      } else {
        _startEstimatedProgressDetection();
      }

      for (var attempt = 0;
          attempt <= maxRetries && !_stopRequested;
          attempt++) {
        if (attempt > 0) {
          debugPrint('[DeviceTTS] retry seg $_currentSegmentIndex '
              'attempt $attempt');
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }

        if (_stopRequested || generation != _speakGeneration) break;

        // FIX 33 — if the error handler scheduled a recovery, bail out
        // of the inner attempt loop so the outer while restarts this
        // segment with a sliced text.
        if (_recoveryPending) break;

        final speakResult = await _adapter.speak(textToSpeak);
        debugPrint('[DeviceTTS] speak returned: $speakResult '
            'attempt=$attempt '
            'gen=$generation');

        if (_stopRequested || generation != _speakGeneration) break;

        if (speakResult == true) {
          if (!_segmentCompletionCompleter!.isCompleted) {
            _segmentCompletionCompleter!.complete();
          }
          break;
        }

        if (_segmentCompletionCompleter!.isCompleted) break;

        if (_stopRequested) break;
      }

      if (_stopRequested || generation != _speakGeneration) break;

      if (!_segmentCompletionCompleter!.isCompleted) {
        await _segmentCompletionCompleter!.future;
      }

      await Future.delayed(const Duration(milliseconds: completionBufferMs));

      if (_stopRequested || generation != _speakGeneration) break;

      final adapter = _adapter;
      if (adapter is WebTtsAdapter) {
        adapter.onSegmentCompleted();
        if (adapter.isEstimatingProgress && !_useEstimatedProgress) {
          _useEstimatedProgress = true;
          _emitEstimating(true);
        }
        if (!adapter.isEstimatingProgress && _useEstimatedProgress) {
          _useEstimatedProgress = false;
          _emitEstimating(false);
        }
      }

      if (_segmentTracker != null && _segmentTracker!.isRunning) {
          final measured = _segmentTracker!.measuredMsPerChar;
          _calibratedMsPerChar = SegmentProgressTracker.combineCalibration(
            _calibratedMsPerChar, measured,
            skipCalibration: segment.hasNumbers,
          );
          debugPrint('[DeviceTTS] calibratedMsPerChar: '
              '$_calibratedMsPerChar (measured: $measured'
              '${segment.hasNumbers ? ', SKIP numbers' : ''})');
        }
      _segmentTracker?.cancel();
      _segmentTracker = null;

      // FIX 33 — only advance if we are NOT in the middle of an
      // auto-recovery for this segment.
      if (!_recoveryPending) {
        _currentSegmentIndex++;
      } else {
        debugPrint('[DeviceTTS] holding seg=$_currentSegmentIndex '
            'for recovery retry');
      }
    }

    if (!_stopRequested && generation == _speakGeneration) {
      _isSegmentSpeaking = false;
      _cancelEstimatedProgress();
      _pendingSegments = [];
      _emitEstimating(false);
      _emit(TtsPlaybackStatus.completed);
    }
  }

  void _completeSegment() {
    debugPrint('[DeviceTTS] completeSegment: speaking=$_isSegmentSpeaking '
        'seg=$_currentSegmentIndex/${_pendingSegments.length}');
    if (!_isSegmentSpeaking) {
      _emit(TtsPlaybackStatus.idle);
      return;
    }
    if (_segmentCompletionCompleter != null &&
        !_segmentCompletionCompleter!.isCompleted) {
      _segmentCompletionCompleter!.complete();
    }
  }

  void _startSegmentTracker(SpeakSegment segment, {int? generation}) {
    generation ??= _speakGeneration;
    _segmentTracker?.cancel();

    final gapThreshold = kIsWeb ? 600 : 400;

    _segmentTracker = SegmentProgressTracker(
      wordCount: segment.words.length,
      globalStartWordIndex: segment.globalStartWordIndex,
      speechRate: _speechRate,
      calibratedMsPerChar: _calibratedMsPerChar,
      audibleCharCount: segment.audibleCharCount,
      silenceGapThresholdMs: gapThreshold,
    );

  _segmentTracker!.start(
    charCount: segment.text.length,
    onWord: (globalIdx) {
      // FIX — capture generation at tracker-creation time so the closure
      // compares against the value that was current when the tracker was
      // started, not the always-equal field. Without this, a tracker
      // created by generation N keeps emitting even after generation N+1
      // has started (e.g. user hit play/stop/play quickly), causing stale
      // word indices to leak into the proxy and produce highlight jumps.
      final gen = generation;
      // Track the last reported local word so auto-recovery can resume
      // close to the interrupt point.
      _lastKnownLocalWordIdx = (globalIdx - segment.globalStartWordIndex)
          .clamp(0, segment.words.isEmpty ? 0 : segment.words.length - 1);
      if (!_wordIndexController.isClosed &&
          _speakGeneration == gen) {
        _wordIndexController.add(globalIdx);
      }
    },
  );
  }

  void _restartSegmentTracker() {
    final seg = _currentEffectiveSegment ??
        (_currentSegmentIndex < _pendingSegments.length
            ? _pendingSegments[_currentSegmentIndex]
            : null);
    if (seg == null) return;
    _startSegmentTracker(seg);
  }

  void _startEstimatedProgressDetection() {
    _progressDetectionTimer?.cancel();
    _progressDetectionTimer = Timer(_progressDetectionWindow, () {
      _progressDetectionTimer = null;
      if (!_receivedRealProgress && _isSegmentSpeaking) {
        _useEstimatedProgress = true;
        _emitEstimating(true);
        // FIX — use the EFFECTIVE segment (which reflects any active
        // recovery slice), not the raw pending segment. Otherwise the
        // tracker emits a global word range that does not match what
        // the engine is actually saying after a recovery, producing a
        // perceptible jump in the highlight.
        final fallbackSeg = _currentEffectiveSegment ??
            (_currentSegmentIndex < _pendingSegments.length
                ? _pendingSegments[_currentSegmentIndex]
                : null);
        if (fallbackSeg != null) {
          _startSegmentTracker(fallbackSeg);
        }
      }
    });
  }

  @override
  Future<Either<Failure, Unit>> stop() async {
    debugPrint('[DeviceTTS] stop() called — '
        'speaking=$_isSegmentSpeaking gen=$_speakGeneration '
        'segIdx=$_currentSegmentIndex/${_pendingSegments.length}');
    // Diagnostic: capture the call site so we can identify which BLoC
    // path is interrupting playback unexpectedly.
    final st = StackTrace.current.toString().split('\n');
    final callers = st.skip(1).take(6).join(' | ');
    debugPrint('[DeviceTTS] stop() callers: $callers');
    // FIX 34 — flag this stop as user-requested so the engine's
    // subsequent "interrupted" error is treated as expected, not a
    // recoverable overflow.
    _userRequestedStop = true;
    _speakGeneration++;
    debugPrint('[DeviceTTS] gen++ (stop) → $_speakGeneration');
    _stopRequested = true;
    _recoveryPending = false;
    _segmentRetryCount = 0;
    _cancelSegmentQueue();
    _cancelEstimatedProgress();
    _progressDetectionTimer?.cancel();
    _progressDetectionTimer = null;
    _isSegmentSpeaking = false;
    _segmentTracker?.cancel();
    _segmentTracker = null;

    try {
      if (_platformSupported) {
        await _adapter.stop().timeout(
              const Duration(milliseconds: 600),
              onTimeout: () {
                debugPrint('[DeviceTTS] stop() timeout — forcing idle');
              },
            );
      }
      _emitEstimating(false);
      _emit(TtsPlaybackStatus.idle);
      return right(unit);
    } catch (e) {
      _emitEstimating(false);
      _emit(TtsPlaybackStatus.idle);
      return left(ServerFailure('TTS stop error: $e'));
    } finally {
      _userRequestedStop = false;
    }
  }

  @override
  Future<Either<Failure, Unit>> setLanguage(String languageCode) async {
    if (!_platformSupported) return right(unit);
    try {
      await _adapter.setLanguage(languageCode);
      return right(unit);
    } catch (e) {
      return left(ServerFailure('TTS setLanguage error: $e'));
    }
  }

  @override
  Future<void> dispose() async {
    debugPrint('[DeviceTTS] dispose() called');
    _speakGeneration++;
    debugPrint('[DeviceTTS] gen++ (dispose) → $_speakGeneration');
    _stopRequested = true;
    _cancelSegmentQueue();
    _cancelEstimatedProgress();
    _progressDetectionTimer?.cancel();
    _progressDetectionTimer = null;
    _segmentTracker?.cancel();
    _segmentTracker = null;
    await _adapter.dispose();
    await _wordIndexController.close();
    await _statusController.close();
    await _estimatingController.close();
    await _recoveryController.close();
  }

  void _emit(TtsPlaybackStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  void _emitEstimating(bool value) {
    if (!_estimatingController.isClosed) {
      _estimatingController.add(value);
    }
  }

  static final digitRegex = RegExp(r'\d+');

  static const numberExpansionFactor = 4;

  static const numberExpansionDict = <String, String>{
    '28': 'veintiocho',
    '1967': 'mil novecientos sesenta y siete',
    '1': 'uno',
    '2': 'dos',
    '3': 'tres',
    '4': 'cuatro',
    '5': 'cinco',
    '6': 'seis',
    '7': 'siete',
    '8': 'ocho',
    '9': 'nueve',
    '10': 'diez',
    '11': 'once',
    '12': 'doce',
    '13': 'trece',
    '14': 'catorce',
    '15': 'quince',
    '16': 'dieciséis',
    '17': 'diecisiete',
    '18': 'dieciocho',
    '19': 'diecinueve',
    '20': 'veinte',
    '30': 'treinta',
    '40': 'cuarenta',
    '50': 'cincuenta',
    '60': 'sesenta',
    '70': 'setenta',
    '80': 'ochenta',
    '90': 'noventa',
    '100': 'cien',
    '200': 'doscientos',
    '500': 'quinientos',
    '1000': 'mil',
  };

  static int computeAudibleCharCount(String text) {
    var count = 0;
    var cursor = 0;
    while (cursor < text.length) {
      final match = digitRegex.matchAsPrefix(text, cursor);
      if (match != null) {
        final numStr = match.group(0)!;
        final expanded = numberExpansionDict[numStr];
        count += expanded != null ? expanded.length : numStr.length * numberExpansionFactor;
        cursor = match.end;
      } else {
        count++;
        cursor++;
      }
    }
    return count;
  }

  static bool detectNumbers(String text) => digitRegex.hasMatch(text);

  /// Splits words into segments of up to [maxWords] words, preserving the
  /// original text alignment.  Exposed as a static method so unit tests
  /// can validate the splitting without standing up the full pipeline.
  static List<SpeakSegment> splitIntoSegments(
    String text,
    List<String> words,
    int globalStartIndex, {
    int maxWords = _maxWordsPerSegment,
  }) {
    if (words.length <= maxWords) {
      final segText = text.isEmpty ? words.join(' ') : text;
      return [
        SpeakSegment(
          text: segText,
          words: words,
          globalStartWordIndex: globalStartIndex,
          audibleCharCount: computeAudibleCharCount(segText),
          hasNumbers: detectNumbers(segText),
        ),
      ];
    }

    // FIX — pre-compute char positions for EVERY word using sequential
    // cursor-based indexOf.  The previous code searched only for the
    // segment's *last* word with `text.indexOf(lastWord, charCursor)`,
    // which performs a **substring** match.  For common Spanish words
    // like "de", this found "de" inside "del" at position 0, truncating
    // the segment text to 2 chars for 200 words.  The resulting
    // text/words mismatch caused `_buildCharOffsets` to map most words
    // to the same offset, making `_binarySearch` return erratic indices
    // (the "se salta varios párrafos" highlight jump to a paragraph
    // with identical text).
    final wordCharPositions = <int>[];
    final wordCharEnds = <int>[];
    {
      int cursor = 0;
      for (final w in words) {
        final idx = text.indexOf(w, cursor);
        if (idx >= 0) {
          wordCharPositions.add(idx);
          wordCharEnds.add(idx + w.length);
          cursor = idx + w.length;
        } else {
          // Word not found — anchor it at cursor so subsequent words
          // still search from the right position.
          wordCharPositions.add(cursor);
          wordCharEnds.add(cursor);
        }
      }
    }

    final segments = <SpeakSegment>[];
    int wordCursor = 0;

    while (wordCursor < words.length) {
      final endWord =
          (wordCursor + maxWords).clamp(0, words.length);
      final segmentWords = words.sublist(wordCursor, endWord);

      String segmentText;
      if (text.isNotEmpty) {
        final charStart = wordCharPositions[wordCursor];
        final charEnd = wordCharEnds[endWord - 1];

        if (charStart < text.length && charEnd > charStart) {
          segmentText = text.substring(charStart, charEnd);
        } else {
          segmentText = segmentWords.join(' ');
        }
      } else {
        segmentText = segmentWords.join(' ');
      }

      // Defensive: log if the segment text is suspiciously short
      // relative to its word count (would mean a mapping problem).
      assert(
        segmentText.length >= segmentWords.length ||
            segmentWords.isEmpty,
        '[_splitIntoSegments] segment text too short: '
        '${segmentText.length} chars for ${segmentWords.length} words',
      );

      segments.add(
        SpeakSegment(
          text: segmentText,
          words: segmentWords,
          globalStartWordIndex: globalStartIndex + wordCursor,
          audibleCharCount: computeAudibleCharCount(segmentText),
          hasNumbers: detectNumbers(segmentText),
        ),
      );
      wordCursor = endWord;
    }

    return segments;
  }

  /// FIX 32 — Hard cap on per-utterance characters.
  ///
  /// The base [splitIntoSegments] partitions by word count, which on Web
  /// can still produce utterances of 2000+ chars (a single long paragraph).
  /// `window.speechSynthesis.speak()` then silently fires
  /// `SpeechSynthesisErrorEvent("interrupted")` once Chrome's empirical
  /// limit (~200 chars) is exceeded. This pass walks each input segment
  /// and emits sub-segments of `<= maxChars`, breaking on the rightmost
  /// punctuation/space within the budget when possible.
  ///
  /// The global word indices of the resulting sub-segments still map 1:1
  /// to the original `words` list — sub-segments simply share contiguous
  /// ranges so the highlight follower keeps working.
  /// True iff the given engine error message indicates an
  /// "interrupted"-class failure (Web Speech overflow, native cancel).
  static bool _isInterruptedMessage(Object? msg) {
    final s = msg?.toString() ?? '';
    if (s.isEmpty) return false;
    if (s == 'interrupted') return true;
    return s.toLowerCase().contains('interrupt');
  }

  /// FIX 33 — Pure predicate exposing the auto-recovery decision so unit
  /// tests can validate the branching without a live FlutterTts engine.
  ///
  /// Returns `true` iff:
  ///   * the engine reported an "interrupted"-class error, AND
  ///   * the user did NOT cause the stop (no in-flight stop()/setVoice()),
  ///     AND
  ///   * we still have recovery budget left ([retryCount] < [maxRetries]).
  static bool shouldAutoRecover({
    required Object? errorMessage,
    required bool userRequestedStop,
    required int retryCount,
    int maxRetries = _maxSegmentRetries,
  }) {
    if (!_isInterruptedMessage(errorMessage)) return false;
    if (userRequestedStop) return false;
    if (retryCount >= maxRetries) return false;
    return true;
  }

  /// Public entry point so tests can validate the splitting behaviour
  /// without standing up the whole pipeline.
  static List<SpeakSegment> enforceMaxSegmentLength(
    List<SpeakSegment> segments,
    int maxChars,
  ) {
    if (maxChars <= 0) return segments;
    final result = <SpeakSegment>[];
    for (final seg in segments) {
      if (seg.text.length <= maxChars) {
        result.add(seg);
        continue;
      }

      // Build word offsets in the original text.
      final wordOffsets = <int>[];
      int cursor = 0;
      for (final w in seg.words) {
        final idx = seg.text.indexOf(w, cursor);
        if (idx >= 0) {
          wordOffsets.add(idx);
          cursor = idx + w.length;
        } else {
          wordOffsets.add(cursor);
        }
      }

      int charCursor = 0;
      int wordCursor = 0;

      while (charCursor < seg.text.length) {
        final remaining = seg.text.length - charCursor;
        int chunkEnd;
        if (remaining <= maxChars) {
          chunkEnd = seg.text.length;
        } else {
          final hardLimit = charCursor + maxChars;

          // FIX: search up to `hardLimit - 1` so that `breakAt + 1`
          // (which includes the punctuation/space char) is guaranteed
          // to be `<= hardLimit`. Without this clamp, a comma sitting
          // exactly at `hardLimit` produced a chunk of length
          // `maxChars + 1` and the per-utterance cap was silently
          // exceeded by 1 char (Chrome interrupted at 181 chars on a
          // 180-char cap).
          final searchLimit = hardLimit - 1;

          // 1) last comma before hardLimit
          var breakAt = seg.text.lastIndexOf(',', searchLimit);
          if (breakAt <= charCursor) breakAt = -1;

          // 2) fallback: last space before hardLimit
          if (breakAt < 0) {
            breakAt = seg.text.lastIndexOf(' ', searchLimit);
            if (breakAt <= charCursor) breakAt = -1;
          }

          // 3) hard cut at maxChars
          if (breakAt < 0) {
            chunkEnd = hardLimit;
          } else {
            chunkEnd = breakAt + 1; // include the comma/space char
          }
        }

        // Determine the word range for this chunk.
        int chunkStartWord;
        int chunkEndWord;
        if (wordCursor >= seg.words.length) {
          // We exhausted the word list (e.g. very long un-spaced word
          // that spans multiple chunks). Attach the trailing chunks to
          // the final word so the highlight follower stays put.
          if (seg.words.isEmpty) {
            chunkStartWord = 0;
            chunkEndWord = 0;
          } else {
            chunkStartWord = seg.words.length - 1;
            chunkEndWord = seg.words.length;
          }
        } else {
          chunkStartWord = wordCursor;
          var advanced = wordCursor;
          while (advanced < seg.words.length &&
              wordOffsets[advanced] < chunkEnd) {
            advanced++;
          }
          if (advanced == chunkStartWord) {
            // Force-include at least one word so we never produce a
            // chunk with zero words (which would make the follower lose
            // the highlight).
            advanced = chunkStartWord + 1;
          }
          chunkEndWord = advanced;
          wordCursor = advanced;
        }

        final chunkWords = chunkEndWord > chunkStartWord
            ? seg.words.sublist(chunkStartWord, chunkEndWord)
            : const <String>[];
        final chunkText = seg.text.substring(charCursor, chunkEnd);

        result.add(
          SpeakSegment(
            text: chunkText,
            words: chunkWords,
            globalStartWordIndex:
                seg.globalStartWordIndex + chunkStartWord,
            audibleCharCount: computeAudibleCharCount(chunkText),
            hasNumbers: detectNumbers(chunkText),
          ),
        );

        charCursor = chunkEnd;
      }
    }
    return result;
  }

  void _cancelSegmentQueue() {
    debugPrint('[DeviceTTS] _cancelSegmentQueue '
        '(speaking=$_isSegmentSpeaking '
        'segIdx=$_currentSegmentIndex/${_pendingSegments.length})');
    _isSegmentSpeaking = false;
    _pendingSegments = [];
    _currentSegmentIndex = 0;
    _currentEffectiveSegment = null;
    _segmentTracker?.cancel();
    _segmentTracker = null;
  }

  void _cancelEstimatedProgress() {
    _progressDetectionTimer?.cancel();
    _progressDetectionTimer = null;
    _useEstimatedProgress = false;
    _segmentTracker?.cancel();
    _segmentTracker = null;
  }

  bool _isPlatformSupported() {
    if (kIsWeb) return true;
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS;
  }

  String _buildSpeakText(String fullText, List<String> words, int startIdx) {
    if (startIdx == 0) return fullText.isNotEmpty ? fullText : words.join(' ');
    if (startIdx >= words.length) return '';

    if (fullText.isEmpty) return words.sublist(startIdx).join(' ');

    int cursor = 0;
    for (int i = 0; i < startIdx; i++) {
      final idx = fullText.indexOf(words[i], cursor);
      if (idx < 0) return words.sublist(startIdx).join(' ');
      cursor = idx + words[i].length;
    }
    final startChar = fullText.indexOf(words[startIdx], cursor);
    if (startChar >= 0) return fullText.substring(startChar);
    return words.sublist(startIdx).join(' ');
  }

  List<int> _buildCharOffsets(String text, List<String> words) {
    final offsets = <int>[];
    int cursor = 0;
    int notFoundCount = 0;
    for (final word in words) {
      final idx = text.indexOf(word, cursor);
      if (idx >= 0) {
        offsets.add(idx);
        cursor = idx + word.length;
      } else {
        offsets.add(cursor);
        notFoundCount++;
      }
    }
    // FIX — diagnostic: if many words are not found in the text, the
    // segment text and words are misaligned. This would cause
    // _binarySearch to map progress events to erratic word indices.
    if (notFoundCount > 0 && words.length > 3) {
      debugPrint('[DeviceTTS] _buildCharOffsets: $notFoundCount/'
          '${words.length} words NOT found in text '
          '(textLen=${text.length}, first3words=${words.take(3).toList()})');
    }
    return offsets;
  }

  int _binarySearch(List<int> offsets, int charPos) {
    int lo = 0, hi = offsets.length - 1, result = 0;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (offsets[mid] <= charPos) {
        result = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return result;
  }
}

class SpeakSegment {
  const SpeakSegment({
    required this.text,
    required this.words,
    required this.globalStartWordIndex,
    required this.audibleCharCount,
    required this.hasNumbers,
  });

  final String text;
  final List<String> words;
  final int globalStartWordIndex;
  final int audibleCharCount;
  final bool hasNumbers;
}
