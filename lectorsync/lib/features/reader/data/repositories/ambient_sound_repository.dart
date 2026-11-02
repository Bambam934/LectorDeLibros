import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/ambient_sound.dart';
import '../audio/ambient_noise_synth.dart';
import '../audio/synth_audio_source.dart';

/// Manages a looped background audio player independent of the TTS
/// engine. Plays ambient sounds (rain, café, fireplace, etc.)
/// alongside the reading voice for immersive sessions.
///
/// Uses its own `AudioPlayer` instance so it never collides with the
/// TTS playback path; both players coexist on Android/iOS/desktop/web.
class AmbientSoundRepository {
  AmbientSoundRepository() : _player = AudioPlayer();

  final AudioPlayer _player;
  AmbientSound? _current;
  double _volume = 0.4;

  AmbientSound? get current => _current;
  double get volume => _volume;
  bool get isPlaying => _player.playing;

  Stream<bool> get playingStream => _player.playingStream;

  static const _kSoundIdKey = 'ambient_sound_id';
  static const _kVolumeKey = 'ambient_sound_volume';
  static const _kEnabledKey = 'ambient_sound_enabled';

  /// Una instancia de [SynthAudioSource] por perfil, reutilizada siempre.
  ///
  /// just_audio registra cada `StreamAudioSource` en el mapa interno de su
  /// proxy HTTP y **nunca la desregistra**: crear una instancia nueva en cada
  /// cambio de preset dejaba el WAV anterior (1,68 MB) retenido para siempre,
  /// y alternar entre ruidos durante una sesión larga acumulaba decenas de MB
  /// irrecuperables.
  ///
  /// Reutilizar la instancia acota el mapa a una entrada por perfil realmente
  /// reproducido: 1,68 MB en el caso normal, 8,4 MB si el usuario llega a
  /// probar los cinco. Es estrictamente mejor que el caché de un solo perfil
  /// que había antes, que retenía lo mismo y además goteaba en cada cambio.
  final Map<String, SynthAudioSource> _synthSources = {};

  /// Carga [sound] en el reproductor según el tipo de fuente.
  ///
  /// Los perfiles `synth:` se sirven desde memoria con [SynthAudioSource] en
  /// vez de escribirse a disco: `dart:io` y `path_provider` no existen en web,
  /// y esta ruta funciona igual en las cinco plataformas.
  Future<void> _loadSource(AmbientSound sound) async {
    if (sound.isSynth) {
      await _player.setAudioSource(await _synthSource(sound));
    } else if (sound.isAsset) {
      await _player.setAsset(sound.assetPath);
    } else {
      await _player.setUrl(sound.source);
    }
    // Loop forever: el ambiente es un fondo continuo. Va aquí, con `await`,
    // y no en el constructor: en Windows, un `play()` justo después de cargar
    // se pierde sin error si no hay otra llamada nativa en medio.
    await _player.setLoopMode(LoopMode.one);
  }

  Future<SynthAudioSource> _synthSource(AmbientSound sound) async {
    final cached = _synthSources[sound.synthProfile];
    if (cached != null) return cached;

    // En un isolate: sintetizar 20 s son ~880.000 muestras y bloquearía el
    // frame si corriera en el hilo de UI.
    final wav = await compute(renderAmbientWav, sound.synthProfile);
    // `??=` por si dos toques seguidos sobre el mismo preset lanzaron dos
    // renders: gana el primero en llegar y el segundo se descarta.
    return _synthSources[sound.synthProfile] ??= SynthAudioSource(wav);
  }

  /// Load the last user-selected sound + volume. Call once at startup.
  Future<void> restorePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kSoundIdKey);
      final vol = prefs.getDouble(_kVolumeKey) ?? 0.4;
      final enabled = prefs.getBool(_kEnabledKey) ?? false;

      _volume = vol.clamp(0.0, 1.0);
      await _player.setVolume(_volume);

      if (id != null) {
        final sound = AmbientSoundPresets.byId(id);
        if (sound != null) {
          _current = sound;
          // Solo se precarga si de verdad va a sonar. Antes se cargaba
          // siempre y el `if (enabled)` gobernaba únicamente el `play()`: un
          // preset sintetizado guardado y APAGADO hacía que cada arranque en
          // frío levantara un isolate, renderizara 20 s de audio y arrancara
          // el reproductor nativo para nada. Y como `stop()` persiste
          // `enabled=false` pero nunca borra el id, el coste era permanente.
          if (enabled) {
            try {
              await _loadSource(sound);
              await _player.play();
            } catch (e) {
              debugPrint('[AmbientSound] preload failed: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AmbientSound] restorePreferences error: $e');
    }
  }

  Future<void> play(AmbientSound sound) async {
    try {
      if (_current?.id != sound.id || _player.audioSource == null) {
        await _player.stop();
        await _loadSource(sound);
        _current = sound;
      }
      await _player.play();
      await _persistEnabled(true);
      await _persistSoundId(sound.id);
    } catch (e) {
      debugPrint('[AmbientSound] play error: $e');
      rethrow;
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
      await _persistEnabled(false);
    } catch (e) {
      debugPrint('[AmbientSound] pause error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
      _current = null;
      await _persistEnabled(false);
    } catch (e) {
      debugPrint('[AmbientSound] stop error: $e');
    }
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kVolumeKey, _volume);
  }

  Future<void> _persistEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, enabled);
  }

  Future<void> _persistSoundId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSoundIdKey, id);
  }

  Future<void> dispose() async {
    _synthSources.clear();
    await _player.dispose();
  }
}

/// Punto de entrada del isolate de [compute]: debe ser una función de nivel
/// superior. Un perfil desconocido cae en ruido rosa — el usuario prefiere un
/// sonido distinto al que pidió antes que ningún sonido.
Uint8List renderAmbientWav(String profileName) {
  final profile = NoiseProfile.values.firstWhere(
    (p) => p.name == profileName,
    orElse: () => NoiseProfile.pink,
  );
  return AmbientNoiseSynth.renderWav(profile);
}
