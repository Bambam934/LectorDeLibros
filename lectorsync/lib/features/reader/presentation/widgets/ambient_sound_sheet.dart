import 'package:flutter/material.dart';

import '../../../../core/di/injection_container.dart';
import '../../data/repositories/ambient_sound_repository.dart';
import '../../domain/entities/ambient_sound.dart';

/// Bottom sheet for choosing and controlling ambient background sound.
///
/// Los presets se sintetizan en el dispositivo (ver `AmbientNoiseSynth`), así
/// que funcionan sin conexión. The sheet also exposes volume and a stop
/// control. Audio plays alongside the TTS engine — they don't interfere.
class AmbientSoundSheet extends StatefulWidget {
  const AmbientSoundSheet({super.key});

  @override
  State<AmbientSoundSheet> createState() => _AmbientSoundSheetState();
}

class _AmbientSoundSheetState extends State<AmbientSoundSheet> {
  late final AmbientSoundRepository _repo;
  bool _playing = false;
  String? _currentId;
  double _volume = 0.4;

  /// Preset que se está preparando ahora mismo, si hay alguno.
  String? _loadingId;

  @override
  void initState() {
    super.initState();
    _repo = sl<AmbientSoundRepository>();
    _playing = _repo.isPlaying;
    _currentId = _repo.current?.id;
    _volume = _repo.volume;
    _repo.playingStream.listen((v) {
      if (mounted) setState(() => _playing = v);
    });
  }

  Future<void> _select(AmbientSound sound) async {
    final messenger = ScaffoldMessenger.of(context);
    // Los presets sintetizados generan 20 s de audio en un isolate antes de
    // sonar. Sin este aviso el usuario toca el preset y no pasa nada durante
    // casi un segundo, así que vuelve a tocarlo.
    setState(() => _loadingId = sound.id);
    try {
      await _repo.play(sound);
      if (mounted) {
        setState(() {
          _currentId = sound.id;
          _playing = true;
          _loadingId = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingId = null);
      // Antes este mensaje decía "verifica tu conexión a internet", que era
      // falso: los presets se generan en el dispositivo y no tocan la red.
      messenger.showSnackBar(SnackBar(
        content: Text('No se pudo reproducir "${sound.label}"'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  Future<void> _pauseOrResume() async {
    if (_playing) {
      await _repo.pause();
    } else if (_currentId != null) {
      final sound = AmbientSoundPresets.byId(_currentId!);
      if (sound != null) await _repo.play(sound);
    }
    if (mounted) setState(() => _playing = _repo.isPlaying);
  }

  Future<void> _stop() async {
    await _repo.stop();
    if (mounted) {
      setState(() {
        _playing = false;
        _currentId = null;
      });
    }
  }

  Future<void> _setVolume(double v) async {
    setState(() => _volume = v);
    await _repo.setVolume(v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Material(
        color: Theme.of(context).bottomSheetTheme.backgroundColor ??
            scheme.surface,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : screenWidth;
                  return SizedBox(
                    width: w,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Icon(Icons.graphic_eq_rounded,
                              color: scheme.primary),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Sonido ambiental',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_currentId != null)
                            IconButton(
                              onPressed: _pauseOrResume,
                              tooltip: _playing ? 'Pausar' : 'Reanudar',
                              icon: Icon(
                                _playing
                                    ? Icons.pause_circle_rounded
                                    : Icons.play_circle_rounded,
                                size: 28,
                                color: scheme.primary,
                              ),
                            ),
                          if (_currentId != null)
                            IconButton(
                              onPressed: _stop,
                              tooltip: 'Detener',
                              icon: Icon(Icons.stop_rounded,
                                  color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              // Volume slider
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.volume_down_rounded,
                        color: scheme.onSurfaceVariant),
                    Expanded(
                      child: Slider(
                        value: _volume,
                        onChanged: _setVolume,
                      ),
                    ),
                    Icon(Icons.volume_up_rounded,
                        color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Presets grid
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: AmbientSoundPresets.all.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    final sound = AmbientSoundPresets.all[index];
                    final selected = sound.id == _currentId;
                    final loading = sound.id == _loadingId;
                    return ListTile(
                      enabled: _loadingId == null,
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: selected
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        child: loading
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: scheme.onSurfaceVariant,
                                ),
                              )
                            : Icon(
                                sound.icon,
                                color: selected
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurfaceVariant,
                              ),
                      ),
                      title: Text(
                        sound.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: selected ? scheme.primary : null,
                        ),
                      ),
                      subtitle: Text(
                        loading
                            ? 'Preparando el sonido…'
                            : (sound.description ?? ''),
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: loading ? FontStyle.italic : null,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: selected && _playing
                          ? Icon(Icons.equalizer_rounded,
                              color: scheme.primary, size: 20)
                          : null,
                      onTap: () => _select(sound),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
