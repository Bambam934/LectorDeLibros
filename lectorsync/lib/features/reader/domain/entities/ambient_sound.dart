import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Represents an ambient sound preset (rain, fireplace, white noise, etc.).
///
/// [source] admite tres formas:
/// - `synth:<perfil>` — se genera en el dispositivo (ver `AmbientNoiseSynth`).
/// - `asset:<ruta>` — grabación empaquetada en la app.
/// - cualquier otra cosa se trata como URL de red.
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

  bool get isSynth => source.startsWith('synth:');
  String get synthProfile => source.replaceFirst('synth:', '');

  @override
  List<Object?> get props => [id, label, source];
}

/// Catálogo de sonidos ambientales.
///
/// Antes todos apuntaban al CDN de Pixabay, que bloquea el hotlinking: los
/// cinco devolvían HTTP 403 (verificado 2026-08-11) y la app culpaba a la
/// conexión del usuario. Ahora ninguno toca la red.
///
/// Los ruidos se generan en el dispositivo (`synth:`), que sale gratis en peso
/// y en licencias. Cafetería y bosque no son ruido estacionario y no se pueden
/// sintetizar de forma convincente, así que van como grabación empaquetada
/// (`asset:`); su autoría está en `assets/audio/CREDITS.md`.
class AmbientSoundPresets {
  static const List<AmbientSound> all = [
    AmbientSound(
      id: 'rain',
      label: 'Lluvia',
      icon: Icons.umbrella_rounded,
      source: 'synth:rain',
      description: 'Lluvia constante que sube y baja',
    ),
    AmbientSound(
      id: 'cafe',
      label: 'Cafetería',
      icon: Icons.local_cafe_rounded,
      source: 'asset:assets/audio/cafe_ambience.mp3',
      description: 'Murmullo de cafetería',
    ),
    AmbientSound(
      id: 'forest',
      label: 'Bosque',
      icon: Icons.forest_rounded,
      source: 'asset:assets/audio/forest_birds.mp3',
      description: 'Pájaros en el bosque',
    ),
    AmbientSound(
      id: 'fire',
      label: 'Chimenea',
      icon: Icons.fireplace_rounded,
      source: 'synth:fire',
      description: 'Crepitar del fuego',
    ),
    AmbientSound(
      id: 'waves',
      label: 'Oleaje',
      icon: Icons.waves_rounded,
      source: 'synth:brown',
      description: 'Ruido marrón, grave y envolvente',
    ),
    AmbientSound(
      id: 'pink_noise',
      label: 'Ruido rosa',
      icon: Icons.blur_on_rounded,
      source: 'synth:pink',
      description: 'Más suave que el blanco, menos fatigante',
    ),
    AmbientSound(
      id: 'white_noise',
      label: 'Ruido blanco',
      icon: Icons.tonality_rounded,
      source: 'synth:white',
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
