import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Lo que el lector ofrece a los controles del sistema.
abstract interface class ReadingCommands {
  Future<void> play();

  Future<void> pause();
}

/// Puente entre los controles del sistema (notificación, pantalla de
/// bloqueo, auriculares) y el lector, para que la voz siga leyendo con la
/// pantalla apagada (ADR 12).
///
/// audio_service mantiene un servicio en primer plano con su notificación, y
/// eso es lo que impide que Android duerma la CPU entre frases o cierre la
/// app. Se configura con `androidStopForegroundOnPause: false`: en Android
/// 12+, volver a poner en primer plano un servicio desde segundo plano lanza
/// `ForegroundServiceStartNotAllowedException`, así que el servicio se queda
/// en primer plano también en pausa. Por eso la notificación pausada no se
/// descarta deslizándola sino con su botón ✕, que llama a [stop].
class ReadingAudioHandler extends BaseAudioHandler {
  ReadingAudioHandler({AudioSession? session}) : _session = session;

  final AudioSession? _session;
  final List<StreamSubscription<Object?>> _interruptionSubs = [];
  ReadingCommands? _commands;
  bool _playing = false;

  /// Hay un libro abierto atendiendo a los controles del sistema. Mientras
  /// lo esté, la voz puede seguir con la app en segundo plano.
  bool get isAttached => _commands != null;

  void attach({
    required String bookId,
    required String bookTitle,
    required ReadingCommands commands,
  }) {
    _commands = commands;
    _playing = false;
    mediaItem.add(MediaItem(id: bookId, title: bookTitle, album: 'LectorSync'));
  }

  /// El capítulo en curso, que la notificación muestra bajo el título.
  void updateChapter(String chapterTitle) {
    final item = mediaItem.value;
    if (item == null || item.artist == chapterTitle) return;
    mediaItem.add(item.copyWith(artist: chapterTitle));
  }

  /// Refleja el estado real de la voz en la notificación.
  Future<void> reportPlaying(bool playing) async {
    if (_commands == null || playing == _playing) return;
    _playing = playing;
    playbackState.add(_stateFor(playing));
    // El foco de audio es lo que hace llegar los avisos de llamada. Solo se
    // pide mientras la voz suena, para no silenciar la música de otras apps
    // con el lector en pausa.
    await _setAudioFocus(playing);
  }

  /// Desconecta el lector (al cerrar el libro) y retira la notificación.
  Future<void> detach() async {
    _commands = null;
    _playing = false;
    await _setAudioFocus(false);
    await super.stop();
  }

  @override
  Future<void> play() async => _commands?.play();

  @override
  Future<void> pause() async => _commands?.pause();

  /// El ✕ de la notificación: pausa la voz y retira la notificación.
  @override
  Future<void> stop() async {
    await _commands?.pause();
    _playing = false;
    await _setAudioFocus(false);
    await super.stop();
  }

  /// Pausa la lectura al desconectar los auriculares o cuando entra una
  /// llamada (ADR 12, sección A.5). No se reanuda sola.
  ///
  /// Recibe los streams y no la sesión para poder probarlo sin plataforma.
  void bindInterruptions({
    required Stream<void> becomingNoisy,
    required Stream<AudioInterruptionEvent> interruptions,
  }) {
    for (final sub in _interruptionSubs) {
      sub.cancel();
    }
    _interruptionSubs
      ..clear()
      ..add(becomingNoisy.listen((_) => pause()))
      ..add(interruptions.listen((event) {
        // `duck` es un aviso breve que solo baja el volumen (navegación, un
        // sonido del sistema): no merece cortar la lectura.
        if (event.begin && event.type != AudioInterruptionType.duck) pause();
      }));
  }

  PlaybackState _stateFor(bool playing) => PlaybackState(
        controls: [
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.stop,
        },
        androidCompactActionIndices: const [0, 1],
        processingState: AudioProcessingState.ready,
        playing: playing,
      );

  Future<void> _setAudioFocus(bool active) async {
    final session = _session;
    if (session == null) return;
    try {
      await session.setActive(active);
    } catch (e) {
      debugPrint('[ReadingAudio] foco de audio: $e');
    }
  }
}
