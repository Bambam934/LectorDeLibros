import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Represents an ambient sound preset (rain, café, fireplace, etc.).
///
/// The [source] is either a network URL or an `asset:` path. Users can
/// also configure a custom URL via the ambient sound sheet.
class AmbientSound extends Equatable {
  const AmbientSound({
    required this.id,
    required this.label,
    required this.icon,
    required this.source,
    this.description,
  });

  final String id;
  final String label;
  final IconData icon;
  final String source;
  final String? description;

  bool get isAsset => source.startsWith('asset:');
  String get assetPath => source.replaceFirst('asset:', '');

  @override
  List<Object?> get props => [id, label, source];
}

/// Curated presets. Sources point to public-domain / royalty-free
/// streaming URLs. If a source becomes unavailable, the user can
/// register a custom URL in the ambient sound sheet.
class AmbientSoundPresets {
  static const List<AmbientSound> all = [
    AmbientSound(
      id: 'rain',
      label: 'Lluvia',
      icon: Icons.umbrella_rounded,
      source:
          'https://cdn.pixabay.com/download/audio/2022/03/15/audio_3776b6fbb6.mp3',
      description: 'Lluvia suave constante',
    ),
    AmbientSound(
      id: 'cafe',
      label: 'Cafetería',
      icon: Icons.local_cafe_rounded,
      source:
          'https://cdn.pixabay.com/download/audio/2022/03/24/audio_36d96f8b66.mp3',
      description: 'Murmullo de cafetería',
    ),
    AmbientSound(
      id: 'fire',
      label: 'Chimenea',
      icon: Icons.fireplace_rounded,
      source:
          'https://cdn.pixabay.com/download/audio/2022/04/12/audio_9c8d7e2b4f.mp3',
      description: 'Crepitar del fuego',
    ),
    AmbientSound(
      id: 'forest',
      label: 'Bosque',
      icon: Icons.forest_rounded,
      source:
          'https://cdn.pixabay.com/download/audio/2021/10/19/audio_309ba5cb95.mp3',
      description: 'Bosque y aves',
    ),
    AmbientSound(
      id: 'white_noise',
      label: 'Ruido blanco',
      icon: Icons.tonality_rounded,
      source:
          'https://cdn.pixabay.com/download/audio/2022/06/07/audio_e93a78b66c.mp3',
      description: 'Ruido blanco neutro',
    ),
  ];

  static AmbientSound? byId(String id) {
    try {
      return all.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }
}
