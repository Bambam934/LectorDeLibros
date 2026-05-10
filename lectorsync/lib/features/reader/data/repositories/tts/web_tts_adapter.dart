import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'tts_adapter.dart';
import 'tts_capabilities.dart';
import 'user_agent_stub.dart'
    if (dart.library.html) 'user_agent_web.dart';
import 'voice_parser.dart';

class WebTtsAdapter implements TtsAdapter {
  WebTtsAdapter() : _tts = FlutterTts() {
    _maxUtteranceChars = _detectMaxUtteranceChars();
  }

  final FlutterTts _tts;
  bool _isInitialized = false;

  int _realProgressEvents = 0;
  int _segmentsSpoken = 0;
  bool _wordBoundaryPermanentlyOff = false;
  late final int _maxUtteranceChars;

  /// Detect browser engine to choose a safe per-utterance char cap.
  /// Safari Desktop interrupts utterances much earlier than Chromium/Firefox
  /// (~100 chars on some voices) so we lower the cap when detected.
  static int _detectMaxUtteranceChars() {
    final ua = readBrowserUserAgent();
    if (ua == null) return TtsCapabilities.web.maxUtteranceChars;
    final lower = ua.toLowerCase();
    final isSafari = lower.contains('safari') &&
        !lower.contains('chrome') &&
        !lower.contains('chromium') &&
        !lower.contains('android');
    if (isSafari) {
      debugPrint('[WebTTS] Safari detected — capping utterance at 100 chars');
      return 100;
    }
    return TtsCapabilities.web.maxUtteranceChars;
  }

  @override
  TtsCapabilities get capabilities =>
      TtsCapabilities.web.copyWith(
        supportsWordBoundary:
            !_wordBoundaryPermanentlyOff && _realProgressEvents > 0,
        maxUtteranceChars: _maxUtteranceChars,
      );

  @override
  FlutterTts get tts => _tts;

  @override
  bool get isInitialized => _isInitialized;

  bool get isEstimatingProgress =>
      _wordBoundaryPermanentlyOff || _realProgressEvents == 0;

  void onRealProgressEvent() {
    _realProgressEvents++;
  }

  void onSegmentCompleted() {
    _segmentsSpoken++;
    if (_segmentsSpoken >= 2 && _realProgressEvents == 0) {
      _wordBoundaryPermanentlyOff = true;
      debugPrint('[WebTTS] 2 segments spoken with zero word-boundary '
          'events — switching to estimated progress permanently');
    }
  }

  void resetSessionState() {
    _realProgressEvents = 0;
    _segmentsSpoken = 0;
    _wordBoundaryPermanentlyOff = false;
  }

  @override
  Future<void> initialize(double speechRate) async {
    if (_isInitialized) return;

    var langResult = await _tts.setLanguage('es-ES');
    if (langResult == null || langResult == -1) {
      langResult = await _tts.setLanguage('es-MX');
    }
    if (langResult == null || langResult == -1) {
      langResult = await _tts.setLanguage('en-US');
    }

    await _tts.setSpeechRate(speechRate);
    await _tts.awaitSpeakCompletion(true);

    _isInitialized = true;
    debugPrint('[WebTTS] initialization complete');
  }

  @override
  Future<dynamic> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<void> setSpeechRate(double rate) => _tts.setSpeechRate(rate);

  @override
  Future<void> setLanguage(String languageCode) =>
      _tts.setLanguage(languageCode);

  @override
  Future<void> setVoice(Map<String, String> voice) async {
    await _tts.setVoice(voice);
    final locale = voice['locale'];
    if (locale != null && locale.isNotEmpty) {
      await _tts.setLanguage(locale);
    }
  }

  @override
  Future<List<Map<String, String>>> getVoices({String? localePrefix}) async {
    try {
      List? raw = await _tts.getVoices;
      if (raw == null || raw.isEmpty) {
        for (var i = 0; i < 5; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          raw = await _tts.getVoices;
          if (raw is List && raw.isNotEmpty) break;
        }
      }
      return parseVoices(raw, localePrefix);
    } catch (e) {
      debugPrint('[WebTTS] getVoices error: $e');
      return const [];
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _tts.stop().timeout(const Duration(milliseconds: 600));
    } catch (_) {}
  }
}
