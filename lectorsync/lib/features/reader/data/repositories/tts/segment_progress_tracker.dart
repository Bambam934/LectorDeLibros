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
  int _currentLocalWordIndex = 0;
  bool _cancelled = false;
  bool _frozen = false;
  DateTime? _lastRealEventTime;

  static const double _baseRate = 0.6;
  static const int _baseMsPerWord = 600;
  static const double _defaultMsPerChar = 50.0;
  static const int _minTimerIntervalMs = 80;

  int get _effectiveCharCount => _audibleCharCount > 0 ? _audibleCharCount : _charCount;

  int get _estimatedMsPerWord {
    final effectiveCharCount = _effectiveCharCount;
    if (_calibratedMsPerChar != null && effectiveCharCount > 0) {
      final avgCharsPerWord = effectiveCharCount / _wordCount;
      return (avgCharsPerWord * _calibratedMsPerChar / (_speechRate / _baseRate))
          .round()
          .clamp(_minTimerIntervalMs, 2000);
    }
    return (_baseMsPerWord / (_speechRate / _baseRate))
        .round()
        .clamp(_minTimerIntervalMs, 2000);
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
    _lastRealEventTime = DateTime.now();
    _stopwatch
      ..reset()
      ..start();

    final interval = Duration(milliseconds: _estimatedMsPerWord);
    _timer = Timer.periodic(interval, (_) {
      if (_cancelled) {
        _cancel();
        return;
      }

      if (_frozen) return;

      _currentLocalWordIndex++;
      if (_currentLocalWordIndex >= _wordCount) {
        _currentLocalWordIndex = _wordCount - 1;
        onWord(_globalStartWordIndex + _currentLocalWordIndex);
        _cancel();
        return;
      }

      onWord(_globalStartWordIndex + _currentLocalWordIndex);
    });
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

  void cancel() {
    _cancelled = true;
    _cancel();
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
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
    if (previous == null) return measured;
    return previous * 0.3 + measured * 0.7;
  }
}
