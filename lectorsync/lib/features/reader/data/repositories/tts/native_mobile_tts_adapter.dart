import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'tts_adapter.dart';
import 'tts_capabilities.dart';
import 'voice_parser.dart';

class NativeMobileTtsAdapter implements TtsAdapter {
  NativeMobileTtsAdapter() : _tts = FlutterTts();

  final FlutterTts _tts;
  bool _isInitialized = false;

  @override
  TtsCapabilities get capabilities => TtsCapabilities.mobile;

  @override
  FlutterTts get tts => _tts;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize(double speechRate) async {
    if (_isInitialized) return;

    try {
      final engines = await _tts.getEngines;
      debugPrint('[MobileTTS] available engines: $engines');
    } catch (_) {
      debugPrint('[MobileTTS] getEngines not supported on this platform');
    }

    var langResult = await _tts.setLanguage('es-ES');
    if (langResult == null || langResult == -1) {
      langResult = await _tts.setLanguage('es-MX');
    }
    if (langResult == null || langResult == -1) {
      langResult = await _tts.setLanguage('en-US');
    }

    await _tts.setSpeechRate(speechRate);

    try {
      final isAvailable = await _tts.isLanguageAvailable('es-ES');
      debugPrint('[MobileTTS] isLanguageAvailable es-ES: $isAvailable');
    } catch (_) {}

    try {
      await _tts.speak('').timeout(const Duration(seconds: 5));
    } catch (_) {}

    _isInitialized = true;
    debugPrint('[MobileTTS] initialization complete');
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
      debugPrint('[MobileTTS] getVoices error: $e');
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
