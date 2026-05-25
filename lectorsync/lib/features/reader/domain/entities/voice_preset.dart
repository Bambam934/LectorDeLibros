import 'package:equatable/equatable.dart';

/// Named bundle of voice + speech-rate configuration that the user can
/// quick-switch between (e.g. "Narrador rápido", "Cuentacuentos pausado").
///
/// Stored locally per-platform — voice IDs from SAPI5/AVSpeech don't map
/// across operating systems, so each device keeps its own preset list.
class VoicePreset extends Equatable {
  const VoicePreset({
    required this.id,
    required this.name,
    required this.speechRate,
    required this.voiceName,
    required this.voiceLocale,
    this.icon = 'mic',
    this.createdAt,
  });

  /// Stable identifier (UUID-ish).
  final String id;

  /// User-facing name ("Narrador rápido", "Voz tranquila", etc.).
  final String name;

  /// Speech rate in the same 0.0–1.0 space the DeviceTtsRepository uses.
  final double speechRate;

  /// Voice display name (matches the engine's voice list).
  final String voiceName;

  /// Voice locale tag (e.g. 'es-MX', 'en-US').
  final String voiceLocale;

  /// Material icon key (kept as string for JSON compatibility).
  final String icon;

  final DateTime? createdAt;

  VoicePreset copyWith({
    String? id,
    String? name,
    double? speechRate,
    String? voiceName,
    String? voiceLocale,
    String? icon,
    DateTime? createdAt,
  }) {
    return VoicePreset(
      id: id ?? this.id,
      name: name ?? this.name,
      speechRate: speechRate ?? this.speechRate,
      voiceName: voiceName ?? this.voiceName,
      voiceLocale: voiceLocale ?? this.voiceLocale,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'speechRate': speechRate,
        'voiceName': voiceName,
        'voiceLocale': voiceLocale,
        'icon': icon,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };

  factory VoicePreset.fromJson(Map<String, dynamic> json) {
    DateTime? created;
    if (json['createdAt'] != null) {
      try {
        created = DateTime.parse(json['createdAt'] as String);
      } catch (_) {}
    }
    return VoicePreset(
      id: json['id'] as String,
      name: json['name'] as String,
      speechRate: (json['speechRate'] as num).toDouble(),
      voiceName: (json['voiceName'] as String?) ?? '',
      voiceLocale: (json['voiceLocale'] as String?) ?? '',
      icon: (json['icon'] as String?) ?? 'mic',
      createdAt: created,
    );
  }

  @override
  List<Object?> get props =>
      [id, name, speechRate, voiceName, voiceLocale, icon];
}
