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
/// audio_service mantiene un servicio en primer plano con su notificación y
/// un wakelock mientras la voz suena: es lo que impide que Android duerma la
/// CPU entre frases o cierre la app. Al pausar sale de primer plano
/// (`androidStopForegroundOnPause: true`), suelta el wakelock y la
/// notificación pasa a poder descartarse. Quedarse en primer plano en pausa
/// (2026-10-03) retenía el wakelock y, como el servicio sigue enlazado, ni
/// cerrar el libro ni la ✕ lo soltaban: CPU despierta hasta que el sistema
/// mataba la app (medido en un Pixel con Android 17).
///
/// Volver a primer plano con la app en segundo plano lanza en Android 12+
/// `ForegroundServiceStartNotAllowedException`, salvo justo después de un
/// botón multimedia. Por eso las paradas de la voz se publican con margen
/// ([pauseGrace]): al pasar de capítulo la voz se para un instante y, con la
/// pantalla apagada, publicar esa pausa la habría dejado sin poder seguir.
class ReadingAudioHandler extends BaseAudioHandler {
  ReadingAudioHandler({
    AudioSession? session,
    this.pauseGrace = const Duration(seconds: 5),
  }) : _session = session;

  /// Cuánto se espera antes de publicar que la voz paró.
  final Duration pauseGrace;

  final AudioSession? _session;
  final List<StreamSubscription<Object?>> _interruptionSubs = [];
  ReadingCommands? _commands;
  bool _playing = false;
  Timer? _pauseTimer;

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

  /// Refleja el estado real de la voz en la notificación. Que suena se
  /// publica al momento; que paró, pasado [pauseGrace] si no vuelve a sonar.
  Future<void> reportPlaying(bool playing) async {
    if (_commands == null) return;
    if (playing) {
      _cancelPauseTimer();
      await _publish(true);
    } else if (_playing && _pauseTimer == null) {
      _schedulePause();
    }
  }

  /// Desconecta el lector (al cerrar el libro) y retira la notificación.
  Future<void> detach() async {
    _commands = null;
    await _leave();
  }

  /// Play de la notificación, la pantalla de bloqueo o los auriculares. Se
  /// publica antes de que la voz arranque, mientras Android aún permite
  /// volver a primer plano; si la voz no llega a sonar, se deshace pasado el
  /// margen.
  @override
  Future<void> play() async {
    final commands = _commands;
    if (commands == null) return;
    _cancelPauseTimer();
    await _publish(true);
    _schedulePause();
    await commands.play();
  }

  /// Pausa del sistema: se publica al momento, sin margen.
  @override
  Future<void> pause() async {
    final commands = _commands;
    if (commands == null) return;
    _cancelPauseTimer();
    await commands.pause();
    await _publish(false);
  }

  /// El ✕ de la notificación: pausa la voz y retira la notificación.
  @override
  Future<void> stop() async {
    await _commands?.pause();
    await _leave();
  }

  /// Un solo estado, parado e `idle` a la vez: audio_service sale de primer
  /// plano (suelta el wakelock) y retira la notificación en el mismo paso.
  /// Con `playing` aún a true no podría quitarla, y publicar antes una pausa
  /// la repintaba: el repintado ganaba la carrera a la retirada y la
  /// notificación se quedaba (visto en el Pixel al cerrar el libro leyendo).
  Future<void> _leave() async {
    _cancelPauseTimer();
    final wasPlaying = _playing;
    _playing = false;
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
    ));
    if (wasPlaying) await _setAudioFocus(false);
  }

  void _schedulePause() {
    _cancelPauseTimer();
    _pauseTimer = Timer(pauseGrace, () {
      _pauseTimer = null;
      unawaited(_publish(false));
    });
  }

  void _cancelPauseTimer() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
  }

  Future<void> _publish(bool playing) async {
    if (playing == _playing) return;
    _playing = playing;
    playbackState.add(_stateFor(playing));
    // El foco de audio es lo que hace llegar los avisos de llamada. Solo se
    // pide mientras la voz suena, para no silenciar la música de otras apps
    // con el lector en pausa.
    await _setAudioFocus(playing);
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
