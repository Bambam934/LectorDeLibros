import 'dart:async';

import 'package:flutter/foundation.dart';

class SegmentProgressTracker {
  SegmentProgressTracker({
    required int wordCount,
    required int globalStartWordIndex,
    required double speechRate,
    double? calibratedMsPerChar,
    int audibleCharCount = 0,
    this.silenceGapThresholdMs = 400,
  }) : _wordCount = wordCount,
       _globalStartWordIndex = globalStartWordIndex,
       _speechRate = speechRate,
       _calibratedMsPerChar = calibratedMsPerChar,
       _audibleCharCount = audibleCharCount,
       _stopwatch = Stopwatch();

  final int _wordCount;
  final int _globalStartWordIndex;
  final double _speechRate;
  final double? _calibratedMsPerChar;
  final int _audibleCharCount;
  final Stopwatch _stopwatch;

  final int silenceGapThresholdMs;

  Timer? _timer;
  Timer? _watchdog;
  int _currentLocalWordIndex = 0;
  DateTime _lastEmitTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _cancelled = false;
  bool _frozen = false;
  DateTime? _lastRealEventTime;
  void Function(int globalWordIndex)? _onWord;

  static const double _baseRate = 0.6;
  // 500ms/word (~120 WPM) measured too slow against real SAPI5 (Microsoft
  // Sabina es-MX) and Chrome Web Speech (Spanish) — both habitually run
  // closer to 150-160 WPM at rate 0.6, i.e. ~380-400 ms/word. The earlier
  // 500ms default caused the highlight to fall ~25% behind the audio for
  // the entire first segment until calibration kicked in on segment 2.
  // 400ms is empirically aligned with both SAPI5 Spanish and Web Speech
  // Spanish; on the rare slow voice the tracker will calibrate up after
  // the first segment via combineCalibration.
  static const int _baseMsPerWord = 400;
  static const double _defaultMsPerChar = 50.0;
  static const int _minTimerIntervalMs = 60;

  // Safe bounds for calibration values. Without these, a single
  // pathological segment (e.g. SAPI5 completing in 0ms or hanging for
  // 90s) can pollute _calibratedMsPerChar to extreme values, making
  // subsequent segments either ultra-fast (highlight overshoots) or
  // ultra-slow (~2s per word feels like the follower is stuck).
  static const double _minMsPerChar = 20.0;
  static const double _maxMsPerChar = 200.0;

  int get _effectiveCharCount => _audibleCharCount > 0 ? _audibleCharCount : _charCount;

  int get _estimatedMsPerWord {
    final effectiveCharCount = _effectiveCharCount;
    if (_calibratedMsPerChar != null && effectiveCharCount > 0) {
      // Defensive: clamp calibration before using it. Even if
      // combineCalibration rejected the bad measurement, a previously
      // stored value might have been outside the safe range.
      final safeMsPerChar =
          _calibratedMsPerChar.clamp(_minMsPerChar, _maxMsPerChar);
      final avgCharsPerWord = effectiveCharCount / _wordCount;
      // Tighter upper bound (was 2000ms). 1100ms/word is already very
      // slow speech; anything beyond that almost certainly means a bad
      // calibration that would make the follower appear stuck.
      return (avgCharsPerWord * safeMsPerChar / (_speechRate / _baseRate))
          .round()
          .clamp(_minTimerIntervalMs, 1100);
    }
    return (_baseMsPerWord / (_speechRate / _baseRate))
        .round()
        .clamp(_minTimerIntervalMs, 1100);
  }

  int _charCount = 0;

  void start({
    required int charCount,
    required void Function(int globalWordIndex) onWord,
  }) {
    _charCount = charCount;
    _cancelled = false;
    _frozen = false;
    _currentLocalWordIndex = 0;
    _lastEmitTime = DateTime.now();
    _onWord = onWord;
    _lastRealEventTime = DateTime.now();
    _stopwatch
      ..reset()
      ..start();

    // Snap the highlight to the FIRST word of this segment immediately.
    // Without this the previous segment's last word remains highlighted
    // until the first Timer.periodic tick fires (~_intervalMs later) —
    // which the user sees as the follower "freezing" for half a beat at
    // every sentence boundary. The proxy de-duplicates by index, so this
    // is a no-op if the highlight was already on _globalStartWordIndex.
    _emitWord(_globalStartWordIndex);

    final intervalMs = _estimatedMsPerWord;
    final interval = Duration(milliseconds: intervalMs);
    _timer = Timer.periodic(interval, (_) {
      if (_cancelled) {
        _cancel();
        return;
      }

      if (_frozen) return;

      _currentLocalWordIndex++;
      if (_currentLocalWordIndex >= _wordCount) {
        _currentLocalWordIndex = _wordCount - 1;
        _emitWord(_globalStartWordIndex + _currentLocalWordIndex);
        _cancel();
        return;
      }

      _emitWord(_globalStartWordIndex + _currentLocalWordIndex);
    });

    // Watchdog: detect when the periodic timer has stopped advancing
    // the highlight (e.g. Flutter timer wheel hiccup on Windows desktop,
    // GC pause, or a freeze that was never properly cleared). If we
    // haven't emitted a new word in 2.5x the expected interval, force
    // a single advance to keep the follower alive. Runs at a
    // deliberately coarser cadence than the main timer to avoid
    // double-advancing in normal operation.
    final watchdogStallThresholdMs = (intervalMs * 2.5).round().clamp(800, 4000);
    _watchdog = Timer.periodic(
      Duration(milliseconds: watchdogStallThresholdMs ~/ 2),
      (_) {
        if (_cancelled) return;
        if (_timer == null) return;
        final sinceEmit =
            DateTime.now().difference(_lastEmitTime).inMilliseconds;
        if (sinceEmit < watchdogStallThresholdMs) return;
        if (_currentLocalWordIndex >= _wordCount - 1) return;
        debugPrint('[Tracker] WATCHDOG stall detected: sinceEmit=${sinceEmit}ms '
            '> threshold=${watchdogStallThresholdMs}ms — force advance '
            'from $_currentLocalWordIndex to ${_currentLocalWordIndex + 1}');
        // Unfreeze defensively (if a stuck `_frozen` flag was the
        // cause) and advance one word so the follower stays alive.
        _frozen = false;
        _currentLocalWordIndex++;
        if (_currentLocalWordIndex >= _wordCount) {
          _currentLocalWordIndex = _wordCount - 1;
        }
        _emitWord(_globalStartWordIndex + _currentLocalWordIndex);
      },
    );
  }

  void _emitWord(int globalIdx) {
    _lastEmitTime = DateTime.now();
    _onWord?.call(globalIdx);
  }

  void notifyRealProgress() {
    final now = DateTime.now();
    if (_lastRealEventTime != null) {
      final gap = now.difference(_lastRealEventTime!).inMilliseconds;
      if (gap > silenceGapThresholdMs && !_frozen) {
        // FIX — diagnostic log so we can see WHICH segments freeze and
        // WHY (large silence gap usually means number expansion). This
        // is the key signal for "28 de Abril de 1967" style bugs.
        debugPrint('[Tracker] FREEZE: gap=${gap}ms > threshold='
            '$silenceGapThresholdMs ms, words=$_wordCount, '
            'charCount=$_charCount, audibleChars=$_audibleCharCount, '
            'localIdx=$_currentLocalWordIndex');
        _frozen = true;
        return;
      }
    }
    _lastRealEventTime = now;
    _frozen = false;
  }

  void unfreeze() {
    _frozen = false;
    _lastRealEventTime = DateTime.now();
  }

  bool get isFrozen => _frozen;

  void updateWordIndex(int localWordIndex) {
    if (localWordIndex > _currentLocalWordIndex) {
      _currentLocalWordIndex = localWordIndex;
    }
  }

  /// Force the tracker's internal cursor to [localWordIndex] without
  /// regard to monotonicity (unlike [updateWordIndex] which only moves
  /// forward). Used by desktop adapters to resync against a sporadic
  /// real-progress event from the engine — the tracker keeps running but
  /// its next emission starts from the corrected position.
  void resyncTo(int localWordIndex) {
    if (localWordIndex < 0) localWordIndex = 0;
    if (_wordCount > 0 && localWordIndex >= _wordCount) {
      localWordIndex = _wordCount - 1;
    }
    _currentLocalWordIndex = localWordIndex;
    _lastRealEventTime = DateTime.now();
    _frozen = false;
  }

  void cancel() {
    _cancelled = true;
    _cancel();
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    _watchdog?.cancel();
    _watchdog = null;
    _onWord = null;
    _stopwatch.stop();
  }

  Duration get elapsed => _stopwatch.elapsed;

  bool get isRunning => _timer != null && !_cancelled;

  int get globalWordIndex => _globalStartWordIndex + _currentLocalWordIndex;

  double get measuredMsPerChar {
    final elapsedMs = _stopwatch.elapsedMilliseconds;
    if (elapsedMs <= 0 || _effectiveCharCount <= 0) return _defaultMsPerChar;
    return elapsedMs / _effectiveCharCount;
  }

  static double? combineCalibration(
    double? previous,
    double measured, {
    bool skipCalibration = false,
  }) {
    if (skipCalibration) return previous;
    // Reject outlier measurements — if the engine completed too fast or
    // too slow to plausibly correspond to actual speech, treat the
    // measurement as noise and keep the previous calibration.
    if (measured < _minMsPerChar || measured > _maxMsPerChar) {
      debugPrint('[Tracker] reject outlier measuredMsPerChar=$measured '
          '(range $_minMsPerChar..$_maxMsPerChar) — keeping previous');
      return previous;
    }
    if (previous == null) return measured;
    // Blend weight bumped from 0.7 measured / 0.3 previous to 0.5 / 0.5.
    // The earlier ratio took ~5 segments to converge from the default to
    // the real voice speed; on Windows where a single segment is 10-15s,
    // that means almost a minute of drift before the highlight tracks
    // tightly. 50/50 still suppresses single-segment noise but reaches
    // the true value in 2-3 segments.
    final blended = previous * 0.5 + measured * 0.5;
    return blended.clamp(_minMsPerChar, _maxMsPerChar);
  }
}
