import 'dart:math';
import 'dart:typed_data';

/// Perfiles de ruido que sabemos sintetizar.
///
/// Todos son señales estacionarias (su espectro no cambia con el tiempo), que
/// es justo la condición para poder reproducirlas en bucle sin que se note el
/// empalme — y también lo que las hace útiles para sostener la concentración.
enum NoiseProfile {
  /// Espectro plano. El clásico "shhh" agudo.
  white,

  /// −3 dB por octava. Más grave y menos fatigante que el blanco.
  pink,

  /// −6 dB por octava. Grave y envolvente, tipo oleaje o viento lejano.
  brown,

  /// Ruido rosa con ráfagas lentas de amplitud: lluvia constante.
  rain,

  /// Ruido marrón con chasquidos aleatorios: crepitar de chimenea.
  fire,
}

/// Sintetiza ruido ambiental como WAV PCM en memoria.
///
/// Sustituye a los presets que apuntaban al CDN de Pixabay: ese CDN bloquea el
/// hotlinking y devolvía HTTP 403 en los cinco sonidos (verificado 2026-08-11),
/// así que la app mostraba "verifica tu conexión" cuando la conexión estaba
/// perfectamente bien.
///
/// Generar el audio en el dispositivo evita las tres causas del fallo de golpe:
/// no hay red que pueda caerse, no hay licencia que gestionar y no engorda el
/// APK. Para sonidos que no son ruido (cafetería, aves) sigue haciendo falta
/// una grabación real: [AmbientSound] admite fuentes `asset:` para eso.
class AmbientNoiseSynth {
  const AmbientNoiseSynth._();

  static const int sampleRate = 44100;

  /// Duración del bucle. Suficientemente largo para que el oído no detecte la
  /// repetición, suficientemente corto para no ocupar más de ~2 MB temporales.
  static const int loopSeconds = 20;

  /// Muestras del solape usado para cerrar el bucle sin chasquido (~50 ms).
  static const int _crossfadeSamples = 2205;

  /// Renderiza [profile] como un WAV PCM 16-bit mono listo para reproducir.
  ///
  /// [seed] fija el generador aleatorio: el mismo perfil produce siempre el
  /// mismo audio, así que el fichero cacheado en disco sigue siendo válido
  /// entre ejecuciones y los tests son deterministas.
  static Uint8List renderWav(NoiseProfile profile, {int seed = 0x5EED}) {
    final samples = _render(profile, seed);
    return _wrapInWavContainer(samples);
  }

  static Float64List _render(NoiseProfile profile, int seed) {
    final total = sampleRate * loopSeconds;
    // Generamos el crossfade de más para poder solapar la cola sobre la cabeza.
    final raw = _generate(profile, total + _crossfadeSamples, seed);
    return _closeLoop(raw, total);
  }

  static Float64List _generate(NoiseProfile profile, int length, int seed) {
    final rnd = Random(seed);
    switch (profile) {
      case NoiseProfile.white:
        return _white(rnd, length, gain: 0.35);
      case NoiseProfile.pink:
        return _pink(rnd, length, gain: 0.5);
      case NoiseProfile.brown:
        return _brown(rnd, length, gain: 0.7);
      case NoiseProfile.rain:
        return _amplitudeDrift(_pink(rnd, length, gain: 0.45), rnd);
      case NoiseProfile.fire:
        return _crackle(_brown(rnd, length, gain: 0.55), rnd);
    }
  }

  static Float64List _white(Random rnd, int length, {required double gain}) {
    final out = Float64List(length);
    for (var i = 0; i < length; i++) {
      out[i] = (rnd.nextDouble() * 2 - 1) * gain;
    }
    return out;
  }

  /// Ruido rosa por el filtro IIR de Paul Kellett: siete polos que aproximan
  /// la pendiente de −3 dB/octava con un coste por muestra constante.
  static Float64List _pink(Random rnd, int length, {required double gain}) {
    final out = Float64List(length);
    var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0;

    for (var i = 0; i < length; i++) {
      final w = rnd.nextDouble() * 2 - 1;
      b0 = 0.99886 * b0 + w * 0.0555179;
      b1 = 0.99332 * b1 + w * 0.0750759;
      b2 = 0.96900 * b2 + w * 0.1538520;
      b3 = 0.86650 * b3 + w * 0.3104856;
      b4 = 0.55000 * b4 + w * 0.5329522;
      b5 = -0.7616 * b5 - w * 0.0168980;
      out[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11 * gain;
      b6 = w * 0.115926;
    }
    return out;
  }

  /// Ruido marrón: integración del blanco con fuga, para que no derive hacia
  /// los extremos y sature.
  static Float64List _brown(Random rnd, int length, {required double gain}) {
    final out = Float64List(length);
    var last = 0.0;
    for (var i = 0; i < length; i++) {
      final w = rnd.nextDouble() * 2 - 1;
      last = (last + 0.02 * w) / 1.02;
      out[i] = last * 3.5 * gain;
    }
    return out;
  }

  /// Modula la amplitud con varias sinusoides lentas e inconmensurables entre
  /// sí. Convierte un ruido plano en algo que "respira" como la lluvia real,
  /// sin que el patrón se repita de forma audible.
  static Float64List _amplitudeDrift(Float64List signal, Random rnd) {
    final phase1 = rnd.nextDouble() * 2 * pi;
    final phase2 = rnd.nextDouble() * 2 * pi;
    for (var i = 0; i < signal.length; i++) {
      final t = i / sampleRate;
      final env = 1 +
          0.18 * sin(2 * pi * 0.07 * t + phase1) +
          0.09 * sin(2 * pi * 0.19 * t + phase2);
      signal[i] *= env;
    }
    return signal;
  }

  /// Añade chasquidos: impulsos dispersos con caída exponencial rápida sobre
  /// el lecho de ruido marrón.
  static Float64List _crackle(Float64List signal, Random rnd) {
    // ~7 chasquidos por segundo, repartidos por todo el bucle.
    final crackles = (signal.length / sampleRate * 7).round();
    for (var c = 0; c < crackles; c++) {
      final at = rnd.nextInt(signal.length);
      final decay = 200 + rnd.nextInt(600);
      final amp = 0.15 + rnd.nextDouble() * 0.25;
      for (var i = 0; i < decay && at + i < signal.length; i++) {
        final env = exp(-i / (decay / 4));
        signal[at + i] += (rnd.nextDouble() * 2 - 1) * amp * env;
      }
    }
    return signal;
  }

  /// Solapa la cola sobre la cabeza para que el final del bucle empalme con su
  /// principio sin el chasquido del salto de amplitud.
  static Float64List _closeLoop(Float64List raw, int total) {
    final out = Float64List(total);
    out.setRange(0, total, raw);

    for (var i = 0; i < _crossfadeSamples; i++) {
      final t = i / _crossfadeSamples;
      out[i] = out[i] * t + raw[total + i] * (1 - t);
    }
    return out;
  }

  /// Empaqueta las muestras en un contenedor WAV mono de 16 bits.
  static Uint8List _wrapInWavContainer(Float64List samples) {
    const headerBytes = 44;
    const bitsPerSample = 16;
    const channels = 1;
    final dataBytes = samples.length * 2;

    final bytes = Uint8List(headerBytes + dataBytes);
    final view = ByteData.view(bytes.buffer);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes[offset + i] = value.codeUnitAt(i);
      }
    }

    writeAscii(0, 'RIFF');
    view.setUint32(4, 36 + dataBytes, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    view.setUint32(16, 16, Endian.little); // tamaño del bloque fmt
    view.setUint16(20, 1, Endian.little); // 1 = PCM sin comprimir
    view.setUint16(22, channels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
    view.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    view.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    view.setUint32(40, dataBytes, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      final clamped = samples[i].clamp(-1.0, 1.0);
      view.setInt16(headerBytes + i * 2, (clamped * 32767).round(), Endian.little);
    }

    return bytes;
  }
}
