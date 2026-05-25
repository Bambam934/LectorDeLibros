import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/voice_preset.dart';

/// Persists user-defined voice presets (named bundles of voice + rate).
///
/// Per-platform storage because voice IDs aren't portable: the same
/// preset name on Windows refers to a SAPI5 voice while on Android it
/// refers to an Android TTS voice. We segment the key with a platform
/// suffix so switching devices doesn't surface incompatible presets.
class VoicePresetRepository {
  static String get _key {
    if (kIsWeb) return 'voice_presets_web';
    return 'voice_presets_native';
  }

  final StreamController<void> _changesController =
      StreamController<void>.broadcast();

  Stream<void> get changes => _changesController.stream;

  void dispose() {
    _changesController.close();
  }

  Future<List<VoicePreset>> getPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <VoicePreset>[];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => VoicePreset.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[VoicePreset] parse error: $e');
      return <VoicePreset>[];
    }
  }

  Future<void> addPreset(VoicePreset preset) async {
    final list = await getPresets();
    // Replace if same ID exists, otherwise append.
    final idx = list.indexWhere((p) => p.id == preset.id);
    if (idx >= 0) {
      list[idx] = preset;
    } else {
      list.add(preset);
    }
    await _save(list);
  }

  Future<void> removePreset(String id) async {
    final list = await getPresets();
    list.removeWhere((p) => p.id == id);
    await _save(list);
  }

  Future<void> _save(List<VoicePreset> list) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(list.map((p) => p.toJson()).toList());
    await prefs.setString(_key, json);
    if (!_changesController.isClosed) _changesController.add(null);
  }
}
