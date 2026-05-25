import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/ambient_sound.dart';

/// Manages a looped background audio player independent of the TTS
/// engine. Plays ambient sounds (rain, café, fireplace, etc.)
/// alongside the reading voice for immersive sessions.
///
/// Uses its own `AudioPlayer` instance so it never collides with the
/// TTS playback path; both players coexist on Android/iOS/desktop/web.
class AmbientSoundRepository {
  AmbientSoundRepository() : _player = AudioPlayer() {
    // Loop forever — ambient sounds are meant to be background bed.
    _player.setLoopMode(LoopMode.one);
  }

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
          // Pre-load URL so playback starts instantly when the user
          // toggles it on, without re-fetching every time.
          try {
            await _player.setUrl(sound.source);
          } catch (e) {
            debugPrint('[AmbientSound] preload failed: $e');
          }
          if (enabled) {
            await _player.play();
          }
        }
      }
    } catch (e) {
      debugPrint('[AmbientSound] restorePreferences error: $e');
    }
  }

  Future<void> play(AmbientSound sound) async {
    try {
      if (_current?.id != sound.id) {
        await _player.stop();
        await _player.setUrl(sound.source);
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
    await _player.dispose();
  }
}
