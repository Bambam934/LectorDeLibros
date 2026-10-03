import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/audio/ambient_noise_synth.dart';

/// Lee las muestras PCM de un WAV mono de 16 bits, saltándose la cabecera.
List<double> _samplesOf(Uint8List wav) {
  final view = ByteData.view(wav.buffer);
  final count = (wav.length - 44) ~/ 2;
  return List<double>.generate(
    count,
    (i) => view.getInt16(44 + i * 2, Endian.little) / 32768,
  );
}

String _ascii(Uint8List wav, int offset, int length) =>
    String.fromCharCodes(wav.sublist(offset, offset + length));

/// Energía media de la diferencia entre muestras consecutivas.
///
/// Es un derivador de primer orden: acentúa los agudos, así que sirve para
/// ordenar los perfiles por brillo sin montar una FFT.
double _highFrequencyEnergy(List<double> samples) {
  var sum = 0.0;
  for (var i = 1; i < samples.length; i++) {
    final d = samples[i] - samples[i - 1];
    sum += d * d;
  }
  return sqrt(sum / (samples.length - 1));
}

void main() {
  group('AmbientNoiseSynth — contenedor WAV', () {
    final wav = AmbientNoiseSynth.renderWav(NoiseProfile.white);

    test('escribe una cabecera RIFF/WAVE válida', () {
      expect(_ascii(wav, 0, 4), 'RIFF');
      expect(_ascii(wav, 8, 4), 'WAVE');
      expect(_ascii(wav, 12, 4), 'fmt ');
      expect(_ascii(wav, 36, 4), 'data');
    });

    test('declara PCM mono de 16 bits a 44,1 kHz', () {
      final view = ByteData.view(wav.buffer);
      expect(view.getUint16(20, Endian.little), 1, reason: 'formato PCM');
      expect(view.getUint16(22, Endian.little), 1, reason: 'canales');
      expect(view.getUint32(24, Endian.little), 44100);
      expect(view.getUint16(34, Endian.little), 16, reason: 'bits por muestra');
    });

    test('los tamaños declarados concuerdan con el buffer real', () {
      final view = ByteData.view(wav.buffer);
      final dataBytes = view.getUint32(40, Endian.little);
      expect(wav.length, 44 + dataBytes);
      expect(view.getUint32(4, Endian.little), 36 + dataBytes);
    });

    test('dura exactamente el bucle configurado', () {
      final samples = _samplesOf(wav);
      expect(
        samples.length,
        AmbientNoiseSynth.sampleRate * AmbientNoiseSynth.loopSeconds,
      );
    });
  });

  group('AmbientNoiseSynth — señal generada', () {
    test('ningún perfil satura ni sale mudo', () {
      for (final profile in NoiseProfile.values) {
        final samples = _samplesOf(AmbientNoiseSynth.renderWav(profile));
        final peak = samples.map((s) => s.abs()).reduce(max);

        expect(peak, lessThanOrEqualTo(1.0), reason: '$profile satura');
        expect(peak, greaterThan(0.05), reason: '$profile suena a silencio');
      }
    });

    test('el brillo decrece de blanco a rosa a marrón', () {
      // Es la definición de cada perfil: −0, −3 y −6 dB por octava.
      final white = _highFrequencyEnergy(
        _samplesOf(AmbientNoiseSynth.renderWav(NoiseProfile.white)),
      );
      final pink = _highFrequencyEnergy(
        _samplesOf(AmbientNoiseSynth.renderWav(NoiseProfile.pink)),
      );
      final brown = _highFrequencyEnergy(
        _samplesOf(AmbientNoiseSynth.renderWav(NoiseProfile.brown)),
      );

      expect(pink, lessThan(white));
      expect(brown, lessThan(pink));
    });

    test('el bucle empalma sin salto de amplitud', () {
      // Un corte brusco entre la última muestra y la primera se oiría como un
      // chasquido en cada vuelta del bucle.
      for (final profile in NoiseProfile.values) {
        final samples = _samplesOf(AmbientNoiseSynth.renderWav(profile));
        final seam = (samples.first - samples.last).abs();

        expect(seam, lessThan(0.25), reason: '$profile chasquea al repetirse');
      }
    });

    test('es determinista: la misma semilla da el mismo audio', () {
      final a = AmbientNoiseSynth.renderWav(NoiseProfile.rain);
      final b = AmbientNoiseSynth.renderWav(NoiseProfile.rain);
      expect(a, equals(b));
    });

    test('perfiles distintos suenan distinto', () {
      final rain = AmbientNoiseSynth.renderWav(NoiseProfile.rain);
      final fire = AmbientNoiseSynth.renderWav(NoiseProfile.fire);
      expect(rain, isNot(equals(fire)));
    });
  });
}
