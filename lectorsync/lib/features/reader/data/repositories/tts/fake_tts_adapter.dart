import 'package:flutter_tts/flutter_tts.dart';

import 'tts_adapter.dart';
import 'tts_capabilities.dart';

class FakeTtsAdapter implements TtsAdapter {
  FakeTtsAdapter({
    this.capabilitiesOverride = TtsCapabilities.mobile,
    this.speakDelay = Duration.zero,
  });

  final TtsCapabilities capabilitiesOverride;
  final Duration speakDelay;

  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  int speakCallCount = 0;
  int stopCallCount = 0;
  List<String> spokenTexts = [];

  @override
  TtsCapabilities get capabilities => capabilitiesOverride;

  @override
  FlutterTts get tts => _tts;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize(double speechRate) async {
    _isInitialized = true;
  }

  @override
  Future<dynamic> speak(String text) async {
    speakCallCount++;
    spokenTexts.add(text);
    if (speakDelay > Duration.zero) {
      await Future.delayed(speakDelay);
    }
    return true;
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> setLanguage(String languageCode) async {}

  @override
  Future<void> setVoice(Map<String, String> voice) async {}

  @override
  Future<List<Map<String, String>>> getVoices({String? localePrefix}) async {
    return const [
      {'name': 'Fake Voice', 'locale': 'es-ES'},
    ];
  }

  @override
  Future<void> dispose() async {}

  void reset() {
    speakCallCount = 0;
    stopCallCount = 0;
    spokenTexts = [];
  }
}
