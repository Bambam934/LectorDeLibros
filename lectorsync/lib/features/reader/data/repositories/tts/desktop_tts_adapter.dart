import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'tts_adapter.dart';
import 'tts_capabilities.dart';
import 'voice_parser.dart';

class DesktopTtsAdapter implements TtsAdapter {
  DesktopTtsAdapter() : _tts = FlutterTts();

  final FlutterTts _tts;
  bool _isInitialized = false;

  @override
  TtsCapabilities get capabilities => TtsCapabilities.desktop;

  @override
  FlutterTts get tts => _tts;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize(double speechRate) async {
    if (_isInitialized) return;

    // Windows SAPI5 / macOS AVSpeechSynthesizer don't expose multiple
    // engines via getEngines — skip entirely to avoid the
    // "getEngines not supported on this platform" warning.

    var langResult = await _tts.setLanguage('es-ES');
    if (langResult == null || langResult == -1) {
      langResult = await _tts.setLanguage('es-MX');
    }
    if (langResult == null || langResult == -1) {
      langResult = await _tts.setLanguage('en-US');
    }

    await _tts.setSpeechRate(speechRate);

    // Skip speak probe on desktop — on Windows SAPI5 the empty-string
    // probe triggers both Success and Error callbacks simultaneously,
    // producing: "Only one of Success, Error, or NotImplemented can be
    // called, and it can be called exactly once."

    _isInitialized = true;
    debugPrint('[DesktopTTS] initialization complete '
        '(${defaultTargetPlatform.name})');
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
      final raw = await _tts.getVoices;
      return parseVoices(raw, localePrefix);
    } catch (e) {
      debugPrint('[DesktopTTS] getVoices error: $e');
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
