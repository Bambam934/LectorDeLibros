import 'package:flutter_tts/flutter_tts.dart';

import 'tts_capabilities.dart';

abstract class TtsAdapter {
  TtsCapabilities get capabilities;
  FlutterTts get tts;
  bool get isInitialized;

  Future<void> initialize(double speechRate);
  Future<dynamic> speak(String text);
  Future<void> stop();
  Future<void> setSpeechRate(double rate);
  Future<void> setLanguage(String languageCode);
  Future<void> setVoice(Map<String, String> voice);
  Future<List<Map<String, String>>> getVoices({String? localePrefix});
  Future<void> dispose();
}
