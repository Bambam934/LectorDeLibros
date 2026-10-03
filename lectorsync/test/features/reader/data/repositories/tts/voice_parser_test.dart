import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/tts/voice_parser.dart';

void main() {
  // Lo que devuelve flutter_tts 4.2.5 en Android (FlutterTtsPlugin.kt).
  final raw = [
    {
      'name': 'es-es-x-eea-network',
      'locale': 'es-ES',
      'network_required': '1',
    },
    {
      'name': 'es-es-x-eea-local',
      'locale': 'es-ES',
      'network_required': '0',
    },
    {'name': 'Microsoft Helena', 'locale': 'es-ES'},
  ];

  test('las voces de red se reconocen por network_required', () {
    final voices = parseVoices(raw, 'es');

    expect(voices.map(voiceNeedsNetwork), [true, false, false]);
  });
}
