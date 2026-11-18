import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/audio_tts_repository.dart';

void main() {
  const signed =
      '/api/v1/audio/3f2b8c1e-9a4d-4e6f-8b2a-1c3d5e7f9a0b-voz.mp3?u=abc&exp=1&sig=x_y-z';

  test('une base y ruta con una sola barra y conserva la firma', () {
    expect(
      AudioTtsRepository.resolveAudioUrl('http://localhost:3000', signed),
      'http://localhost:3000$signed',
    );
    expect(
      AudioTtsRepository.resolveAudioUrl('https://api.ejemplo.com/', signed),
      'https://api.ejemplo.com$signed',
    );
  });

  test('una URL absoluta se respeta', () {
    const absolute = 'https://cdn.ejemplo.com/a.mp3';
    expect(AudioTtsRepository.resolveAudioUrl('http://localhost:3000', absolute), absolute);
  });
}
