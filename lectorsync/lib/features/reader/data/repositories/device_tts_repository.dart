import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/sorted_lookup.dart';
import '../../domain/repositories/tts_repository.dart';
import 'tts/desktop_tts_adapter.dart';
import 'tts/language_detector.dart';
import 'tts/native_mobile_tts_adapter.dart';
import 'tts/segment_progress_tracker.dart';
import 'tts/speak_segment.dart';
import 'tts/tts_adapter.dart';
import 'tts/tts_capabilities.dart';
import 'tts/tts_segmentation.dart' as seg;
import 'tts/web_tts_adapter.dart';

// SpeakSegment y la segmentación pura se extrajeron a tts/ (2026-07-19).
// El tipo se re-exporta para no romper a quien lo importa desde aquí.
export 'tts/speak_segment.dart' show SpeakSegment;

class DeviceTtsRepository implements TtsRepository {
  DeviceTtsRepository() : _adapter = _createAdapter();

  static TtsAdapter _createAdapter() {
    if (kIsWeb) return WebTtsAdapter();
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return DesktopTtsAdapter();
      default:
        return NativeMobileTtsAdapter();
    }
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
  static const int _maxWordsPerSegment = seg.kMaxWordsPerSegment;

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
  static const int _maxSegmentRetries = seg.kMaxSegmentRetries;

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

  /// Segment whose tracker should be started the moment the engine's
  /// startHandler fires. We park the segment here in `_speakSegmentLoop`
  /// instead of starting the tracker immediately, so the tracker's
  /// stopwatch aligns with the actual audio output on platforms whose
  /// engines take noticeable time between speak() and the first audible
  /// word (Windows SAPI5 ~200-500ms). Without this offset correction the
  /// estimated tracker runs ~1 word ahead of the voice for the entire
  /// segment, which is the dominant cause of perceived desync on Windows.
  SpeakSegment? _pendingTrackerSegment;
  int? _pendingTrackerGeneration;

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
  String? _detectedLanguage;
  bool autoLanguageEnabled = true;

  // ── Calibration persistence ─────────────────────────────────────────
  //
  // The estimated-tracker baseline (_calibratedMsPerChar) is only useful
  // *after* the first segment of a reading session has finished. With the
  // earlier in-memory-only model, every fresh app launch (and every
  // play/pause cycle on platforms without word boundaries) had to re-pay
  // that "first segment is uncalibrated" cost — which is precisely the
  // window the user perceives as "the highlight is lagging the voice".
  //
  // Persisting the latest calibration per (platform, voice) lets the very
  // next play() — even after a full app restart — start with a tracker
  // already aligned to the real engine speed. We deliberately key on the
  // voice name because different voices (Microsoft Sabina vs Microsoft
  // Helena, Chrome default vs Edge default) have measurably different
  // characters-per-second rates and sharing a single number across all of
  // them would re-introduce drift after a voice swap.
  static const String _calibrationKeyPrefix = 'tts_calibration_msPerChar';

  String get _platformTag {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  String get _calibrationKey {
    final voice = _selectedVoice?['name'] ?? 'default';
    return '${_calibrationKeyPrefix}_${_platformTag}_$voice';
  }

  Future<void> _loadCalibration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getDouble(_calibrationKey);
      if (stored != null && stored >= 20 && stored <= 200) {
        _calibratedMsPerChar = stored;
        debugPrint('[DeviceTTS] loaded persisted calibration: '
            'key=$_calibrationKey msPerChar=$stored');
      }
    } catch (e) {
      debugPrint('[DeviceTTS] loadCalibration failed: $e');
    }
  }

  Future<void> _persistCalibration() async {
    final value = _calibratedMsPerChar;
    if (value == null || value < 20 || value > 200) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_calibrationKey, value);
    } catch (e) {
      debugPrint('[DeviceTTS] persistCalibration failed: $e');
    }
  }

  Map<String, String>? get selectedVoice => _selectedVoice;

  String? get detectedLanguage => _detectedLanguage;

  TtsCapabilities get capabilities => _adapter.capabilities;

  bool get isEstimatingProgress {
    // Platforms without reliable word-boundary events always estimate.
    if (!_adapter.capabilities.supportsWordBoundary) return true;
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
      // Voices have measurably different cadences. Drop the in-memory
      // calibration (which was tuned for the previous voice) and load
      // the persisted value for this voice, if any. Otherwise the next
      // segment would inherit a stale msPerChar and the highlight would
      // drift again until segment 2.
      _calibratedMsPerChar = null;
      unawaited(_loadCalibration());
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
        // Latency-corrected tracker start. _speakSegmentLoop parks the
        // segment in _pendingTrackerSegment instead of starting the
        // tracker eagerly; we only kick the timer wheel here, when the
        // engine confirms it has begun producing audio. On Windows SAPI5
        // this removes a 200-500ms "tracker is already running but no
        // sound yet" window that used to leave the highlight one full
        // word ahead of the voice for the entire segment.
        final pending = _pendingTrackerSegment;
        final pendingGen = _pendingTrackerGeneration;
        if (pending != null &&
            pendingGen == _speakGeneration &&
            _useEstimatedProgress &&
            _isSegmentSpeaking) {
          _pendingTrackerSegment = null;
          _pendingTrackerGeneration = null;
          _startSegmentTracker(pending);
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

        // Desktop (SAPI5/AVSpeech): progress events are sporadic and
        // unreliable, but the few that arrive ARE accurate. Use them to
        // RESYNC the tracker (without cancelling it) so the follower
        // self-corrects over time and stays close to the actual voice.
        if (!_adapter.capabilities.supportsWordBoundary) {
          if (_segmentTracker != null && _segmentTracker!.isRunning) {
            final localIdx = _binarySearch(_charOffsets, start);
            _segmentTracker!.resyncTo(localIdx);
            _lastKnownLocalWordIdx = localIdx;
            // Emit immediately so the highlight snaps to the verified
            // word, then the timer resumes from there.
            final globalIdx = _startOffset + localIdx;
            if (!_wordIndexController.isClosed) {
              _wordIndexController.add(globalIdx);
            }
          }
          return;
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
          '(adapter: ${_adapter.runtimeType})');

      // Hydrate the calibration cache so the first segment of the user's
      // very first play() this session already uses last session's
      // measured msPerChar, instead of the conservative _baseMsPerWord
      // default. Best-effort and fire-and-forget — failure here just
      // means we fall back to the default for one segment.
      unawaited(_loadCalibration());

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

    // Auto-detect language from text content and configure TTS accordingly.
    // Only if no voice was manually selected (which already sets its locale).
    if (autoLanguageEnabled && _selectedVoice == null && text.isNotEmpty) {
      final detected = LanguageDetector.detect(text);
      if (detected != _detectedLanguage) {
        _detectedLanguage = detected;
        debugPrint('[DeviceTTS] auto-detected language: $detected');
        try {
          await _adapter.setLanguage(detected);
        } catch (e) {
          debugPrint('[DeviceTTS] setLanguage($detected) failed: $e');
        }
      }
    }

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

      // Previously we always reset _calibratedMsPerChar at the start of
      // each speak() on platforms without word boundaries — but that
      // meant every play/pause cycle threw away the calibration and the
      // first segment had to use _baseMsPerWord again (visibly slower
      // than the real voice). combineCalibration already rejects
      // out-of-bounds samples (20..200 ms/char), so we keep any value
      // that's already inside the safe range and only nuke obvious
      // garbage. Result: pressing pause→play resumes with the right
      // timing instead of re-introducing the initial drift every time.
      final cached = _calibratedMsPerChar;
      if (cached != null && (cached < 20 || cached > 200)) {
        debugPrint('[DeviceTTS] discarding out-of-bounds cached '
            'msPerChar=$cached at speak() start');
        _calibratedMsPerChar = null;
      }

      final clampedStart =
          startWordIndex.clamp(0, words.isEmpty ? 0 : words.length - 1);

      final speakWords =
          clampedStart > 0 ? words.sublist(clampedStart) : words;
      final speakText = _buildSpeakText(text, words, clampedStart);

      // FIX 78 (session 16) — split by SENTENCE first only on platforms
      // that depend on the timer-based estimated tracker (Web Speech,
      // Windows SAPI5, macOS AVSpeech). Aligning segment boundaries
      // with the engine's natural pauses (`.`, `!`, `?`, `;`) absorbs
      // those pauses at segment-swap time where the tracker resets,
      // instead of letting the timer drift past them mid-utterance.
      //
      // On Android / iOS (`supportsWordBoundary = true`) the engine
      // emits real per-word progress events, so the tracker is never
      // used and there is no drift to fix. Sentence-splitting would
      // just chop a smooth audio stream into many tiny utterances and
      // introduce ~50-100 ms of inter-utterance latency on each one
      // (the engine has its own startup cost per `speak()` call).
      // That degrades a flow the user already considers ideal, so we
      // explicitly skip sentence-splitting on those platforms.
      //
      // enforceMaxSegmentLength still runs everywhere so Web's 180-char
      // utterance cap and SAPI5's 800-char practical limit are honoured.
      final segmentProse = _adapter.capabilities.supportsWordBoundary
          ? splitIntoSegments
          : splitIntoSentences;
      // Aislar los párrafos-fórmula ANTES de segmentar la prosa. La
      // heurística mide proporciones del bloque entero y está calibrada para
      // un párrafo: corriéndola sobre trozos de 200 palabras (o sobre
      // oraciones ya fusionadas con su vecina) no se disparaba nunca, y la
      // voz leía la ecuación aplanada aunque la pantalla la pintara como
      // fórmula. Ver `splitIsolatingFormulas`.
      final initialSegments = seg.splitIsolatingFormulas(
        speakText,
        speakWords,
        clampedStart,
        segmentProse: segmentProse,
      );
      // Silenciar las fórmulas ANTES de trocear por longitud: el texto ya
      // sustituido es corto y no hay nada que partir. Al revés, una fórmula
      // larga se habría repartido en varios trozos y cada uno diría
      // "Fórmula." por separado.
      _pendingSegments = enforceMaxSegmentLength(
        seg.muteFormulaSegments(initialSegments),
        _adapter.capabilities.maxUtteranceChars,
      );
      _currentSegmentIndex = 0;
      _isSegmentSpeaking = true;
      _stopRequested = false;
      _receivedRealProgress = false;

      // Platforms without reliable word-boundary events (desktop SAPI5,
      // Web Speech after detection) must use the timer-based estimated
      // progress tracker from the very first segment.
      final adapter = _adapter;
      final forceEstimated = !_adapter.capabilities.supportsWordBoundary;
      if (forceEstimated ||
          (adapter is WebTtsAdapter && adapter.isEstimatingProgress)) {
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
        if (segment.isFormula) {
          // El texto de una fórmula silenciada es un aviso, no se deriva de
          // `words`: reconstruirlo desde ahí devolvería la ecuación aplanada
          // que el aviso vino a sustituir. Se repite el aviso entero, que
          // dura menos de un segundo.
          effectiveWords = segment.words;
          textToSpeak = segment.text;
          effectiveStartWord = segment.globalStartWordIndex;
        } else {
          effectiveWords = segment.words.sublist(localStart);
          textToSpeak = effectiveWords.join(' ');
          effectiveStartWord = segment.globalStartWordIndex + localStart;
        }
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
              isFormula: segment.isFormula,
            )
          : segment;
      _currentEffectiveSegment = trackerSegment;

      if (_useEstimatedProgress) {
        // Defer tracker start until startHandler fires (see comment on
        // _pendingTrackerSegment). Falls back to immediate start if the
        // engine never fires startHandler within ~700ms, so we never
        // leave the highlight completely frozen.
        _pendingTrackerSegment = trackerSegment;
        _pendingTrackerGeneration = generation;
        final guardedGen = generation;
        Future<void>.delayed(const Duration(milliseconds: 700), () {
          if (_pendingTrackerSegment != null &&
              _pendingTrackerGeneration == guardedGen &&
              _useEstimatedProgress &&
              _isSegmentSpeaking) {
            debugPrint('[DeviceTTS] tracker fallback start '
                '(no startHandler within 700ms) seg=$_currentSegmentIndex');
            final segToStart = _pendingTrackerSegment!;
            _pendingTrackerSegment = null;
            _pendingTrackerGeneration = null;
            _startSegmentTracker(segToStart);
          }
        });
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

        // FIX 82 (session 17) — `flutter_tts.speak()` reports success
        // with different types per platform: `true` on iOS / Web,
        // integer `1` on Android / Windows / macOS. The previous
        // `speakResult == true` check was true ONLY for the bool case,
        // so on Android we silently took the retry path even after a
        // perfectly successful utterance — re-issuing the SAME text
        // ~500 ms later, which the user heard as the chapter restarting
        // and saw as the highlight jumping back to the start of the
        // segment. Treat both shapes as success.
        final isSuccess = speakResult == true || speakResult == 1;
        if (isSuccess) {
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
          final before = _calibratedMsPerChar;
          // We used to skip calibration for segments containing digits
          // (e.g. "1967", dates) on the assumption that number
          // expansion would skew the timing. But the tracker's
          // `_effectiveCharCount` already counts the expanded form via
          // `computeAudibleCharCount`, so the measured ms/char IS valid
          // for those segments. Skipping just delayed convergence on
          // texts with frequent dates / numbered headings.
          _calibratedMsPerChar = SegmentProgressTracker.combineCalibration(
            _calibratedMsPerChar, measured,
            skipCalibration: false,
          );
          debugPrint('[DeviceTTS] calibratedMsPerChar: '
              '$_calibratedMsPerChar (measured: $measured)');
          // Persist asynchronously so the next session starts already
          // calibrated. Only write if the value actually changed and is
          // inside the safe range (the persist method also guards).
          if (_calibratedMsPerChar != null &&
              _calibratedMsPerChar != before) {
            unawaited(_persistCalibration());
          }
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

  void _startSegmentTracker(
    SpeakSegment segment, {
    int? generation,
    int resumeAtLocalWord = 0,
  }) {
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
  // Seed the tracker at the requested resume point. Used when speech
  // rate changes mid-segment: the engine keeps speaking from where it
  // was, so the new tracker must start from the last known local word
  // instead of jumping the highlight back to the segment start.
  if (resumeAtLocalWord > 0) {
    _segmentTracker!.resyncTo(resumeAtLocalWord);
  }
  }

  void _restartSegmentTracker() {
    final seg = _currentEffectiveSegment ??
        (_currentSegmentIndex < _pendingSegments.length
            ? _pendingSegments[_currentSegmentIndex]
            : null);
    if (seg == null) return;
    // FIX — when restarting mid-segment (e.g. user dragged the speed
    // slider and we re-derive the tick interval for the new rate), the
    // engine keeps speaking from where it is, so the new tracker must
    // resume at the last known local word — NOT reset to 0. Resetting
    // to 0 caused the highlight to jump backwards to the start of the
    // current segment every time speed changed.
    final resumeAt = _lastKnownLocalWordIdx.clamp(
      0,
      seg.words.isEmpty ? 0 : seg.words.length - 1,
    );
    _startSegmentTracker(seg, resumeAtLocalWord: resumeAt);
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

    // Capture an in-flight calibration sample BEFORE we tear down the
    // tracker. Without this, a user who pause/restart-spams on Windows
    // (because the highlight looks ahead of the voice) never lets a
    // segment complete, so _calibratedMsPerChar stays null forever and
    // the next speak() falls back to the conservative 400ms/word base
    // again. Sampling here lets us learn from partial segments too as
    // long as they ran long enough to be meaningful.
    final liveTracker = _segmentTracker;
    if (liveTracker != null && liveTracker.isRunning) {
      final elapsedMs = liveTracker.elapsed.inMilliseconds;
      if (elapsedMs >= 3000) {
        final measured = liveTracker.measuredMsPerChar;
        final before = _calibratedMsPerChar;
        _calibratedMsPerChar = SegmentProgressTracker.combineCalibration(
          _calibratedMsPerChar,
          measured,
          // Sampling at stop() is best-effort — we always accept the
          // measurement here, including for segments that contained
          // numbers. computeAudibleCharCount already inflates the
          // denominator for expanded digits so the ratio is a sensible
          // approximation.
          skipCalibration: false,
        );
        debugPrint('[DeviceTTS] partial calibration at stop: '
            'measured=$measured elapsed=${elapsedMs}ms '
            'before=$before after=$_calibratedMsPerChar');
        if (_calibratedMsPerChar != null &&
            _calibratedMsPerChar != before) {
          unawaited(_persistCalibration());
        }
      }
    }

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

  // La segmentación pura se extrajo a `tts/tts_segmentation.dart`
  // (2026-07-19). Estos miembros estáticos delegan para no romper a sus
  // llamadores, que la usan vía DeviceTtsRepository (los tests incluidos).
  static final digitRegex = seg.digitRegex;

  static const numberExpansionFactor = seg.numberExpansionFactor;

  static const numberExpansionDict = seg.numberExpansionDict;

  static int computeAudibleCharCount(String text) =>
      seg.computeAudibleCharCount(text);

  static bool detectNumbers(String text) => seg.detectNumbers(text);

  /// Segmentación base por conteo de palabras. La implementación vive en
  /// `tts/tts_segmentation.dart`; aquí se delega por compatibilidad.
  static List<SpeakSegment> splitIntoSegments(
    String text,
    List<String> words,
    int globalStartIndex, {
    int maxWords = _maxWordsPerSegment,
  }) =>
      seg.splitIntoSegments(text, words, globalStartIndex, maxWords: maxWords);

  /// FIX 78 (session 16) — Sentence-aligned segmentation.
  ///
  /// The single largest source of perceived desync between the highlight
  /// and the spoken audio on Windows SAPI5 and Web Speech is that those
  /// engines insert *natural* pauses at sentence-ending punctuation
  /// (`.`, `!`, `?`, `;`) — anywhere from ~150 ms (semicolon) up to
  /// ~500 ms (period followed by paragraph break). The timer-based
  /// SegmentProgressTracker has no way to know about those pauses: it
  /// keeps advancing at the estimated ms/word rate, so once the engine
  /// has paused N times mid-segment the highlight is N×~300 ms ahead of
  /// the voice. With a single 800-char (~130-word) Windows segment that
  /// contains 5–8 sentences, the cumulative drift exceeds three words
  /// before the segment ends — which the user perceives as "totally
  /// desynchronised" right after the first paragraph.
  ///
  /// The industry-standard fix used by Voice Dream Reader, NaturalReader
  /// on Windows, and Speechify when running on top of SAPI5 / Web Speech
  /// is to give each *sentence* its own utterance:
  ///
  ///   • The engine's pause coincides with the boundary between two of
  ///     OUR segments, where the tracker is destroyed and recreated for
  ///     the next sentence — the pause is absorbed for free.
  ///   • Calibration error cannot accumulate across sentences, because
  ///     the tracker resets at every boundary.
  ///   • The next sentence's tracker is fully re-seeded with the last
  ///     calibrated ms/char, so it starts already tuned.
  ///
  /// This method splits `text` at sentence-ending punctuation followed
  /// by whitespace, while keeping each segment's `words` slice aligned
  /// with the original word list (so the highlight follower keeps
  /// working). Very short fragments (<30 chars, e.g. "Sí.") are merged
  /// with their neighbour to avoid choppy speech and excessive engine
  /// thrash. If the source text has no punctuation at all (some
  /// poetry, weird OCR output), the whole input is returned as a single
  /// segment and the existing `enforceMaxSegmentLength` will cap it.
  static List<SpeakSegment> splitIntoSentences(
    String text,
    List<String> words,
    int globalStartIndex, {
    int minMergeChars = 30,
  }) =>
      seg.splitIntoSentences(text, words, globalStartIndex,
          minMergeChars: minMergeChars);

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
  static bool _isInterruptedMessage(Object? msg) =>
      seg.isInterruptedMessage(msg);

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
  }) =>
      seg.shouldAutoRecover(
        errorMessage: errorMessage,
        userRequestedStop: userRequestedStop,
        retryCount: retryCount,
        maxRetries: maxRetries,
      );

  /// Public entry point so tests can validate the splitting behaviour
  /// without standing up the whole pipeline.
  static List<SpeakSegment> enforceMaxSegmentLength(
    List<SpeakSegment> segments,
    int maxChars,
  ) =>
      seg.enforceMaxSegmentLength(segments, maxChars);

  void _cancelSegmentQueue() {
    debugPrint('[DeviceTTS] _cancelSegmentQueue '
        '(speaking=$_isSegmentSpeaking '
        'segIdx=$_currentSegmentIndex/${_pendingSegments.length})');
    _isSegmentSpeaking = false;
    _pendingSegments = [];
    _currentSegmentIndex = 0;
    _currentEffectiveSegment = null;
    _pendingTrackerSegment = null;
    _pendingTrackerGeneration = null;
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
    // Ninguna palabra aparece en el texto: el segmento se pronuncia con un
    // texto distinto del que representa — el caso de una fórmula sustituida
    // por "Fórmula.". Con todos los offsets a 0, `_binarySearch` devuelve el
    // ÚLTIMO índice para charPos=0 y el resaltado saltaba de golpe al final
    // del bloque en cuanto arrancaba el aviso. Repartir las palabras a lo
    // largo del texto hace que el seguidor las recorra durante el aviso, que
    // es justo lo que promete `muteFormulaSegments`.
    if (notFoundCount == words.length && words.length > 1 && text.isNotEmpty) {
      return [
        for (var i = 0; i < words.length; i++) (i * text.length) ~/ words.length,
      ];
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

  /// Palabra que corresponde a [charPos] dentro del segmento en curso.
  ///
  /// Cae en 0 cuando no hay offsets o la posición es anterior al primero: el
  /// seguidor prefiere quedarse al principio del segmento antes que recibir
  /// un índice negativo.
  int _binarySearch(List<int> offsets, int charPos) {
    final idx = lastOffsetAtOrBefore(offsets, charPos);
    return idx < 0 ? 0 : idx;
  }
}
