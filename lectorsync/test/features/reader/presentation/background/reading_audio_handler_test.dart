import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/presentation/background/reading_audio_handler.dart';

class _FakeCommands implements ReadingCommands {
  final List<String> calls = [];

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');
}

void main() {
  late ReadingAudioHandler handler;
  late _FakeCommands commands;

  setUp(() {
    handler = ReadingAudioHandler(pauseGrace: const Duration(milliseconds: 50));
    commands = _FakeCommands();
  });

  void attach() => handler.attach(
        bookId: 'b1',
        bookTitle: 'Cálculo integral',
        commands: commands,
      );

  Future<void> afterGrace() =>
      Future<void>.delayed(const Duration(milliseconds: 150));

  /// Los estados que recibe audio_service desde ahora, en orden.
  Future<List<PlaybackState>> Function() recordStates() {
    final states = <PlaybackState>[];
    final sub = handler.playbackState.listen(states.add);
    return () async {
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      return states;
    };
  }

  /// En Android, audio_service solo retira la notificación si en el mismo
  /// estado sale de primer plano: `idle` tiene que llegar ya parado, y sin
  /// una pausa intermedia, que la repinta y gana la carrera a la retirada.
  void expectLeavesInOneStep(List<PlaybackState> states) {
    final idle = states.indexWhere(
      (s) => s.processingState == AudioProcessingState.idle,
    );
    expect(idle, greaterThan(0));
    expect(states[idle].playing, isFalse, reason: 'idle llega ya parado');
    expect(
      states.take(idle).where(
            (s) => s.processingState == AudioProcessingState.ready && !s.playing,
          ),
      isEmpty,
      reason: 'sin pausa intermedia que repinte la notificación',
    );
  }

  test('al abrir un libro, la notificación lleva su título', () {
    attach();

    expect(handler.isAttached, isTrue);
    expect(handler.mediaItem.value?.title, 'Cálculo integral');
  });

  test('el capítulo aparece bajo el título', () {
    attach();
    handler.updateChapter('Capítulo 3');

    expect(handler.mediaItem.value?.artist, 'Capítulo 3');
  });

  test('refleja que la voz suena, con el botón de pausa', () async {
    attach();
    await handler.reportPlaying(true);

    final state = handler.playbackState.value;
    expect(state.playing, isTrue);
    expect(state.controls.first, MediaControl.pause);
    expect(state.processingState, AudioProcessingState.ready);
  });

  test('la parada de la voz se publica pasado el margen', () async {
    attach();
    await handler.reportPlaying(true);
    await handler.reportPlaying(false);

    expect(handler.playbackState.value.playing, isTrue, reason: 'aún en margen');

    await afterGrace();
    final state = handler.playbackState.value;
    expect(state.playing, isFalse);
    expect(state.controls.first, MediaControl.play);
  });

  test('un salto de capítulo no llega a publicar la pausa', () async {
    // Con la pantalla apagada, publicarla sacaría al servicio de primer
    // plano y Android ya no le dejaría volver para el capítulo siguiente.
    attach();
    await handler.reportPlaying(true);
    await handler.reportPlaying(false);
    await handler.reportPlaying(true);
    await afterGrace();

    expect(handler.playbackState.value.playing, isTrue);
  });

  test('los botones del sistema llegan al lector', () async {
    attach();
    await handler.play();
    await handler.pause();

    expect(commands.calls, ['play', 'pause']);
  });

  test('pausar desde la notificación es inmediato', () async {
    attach();
    await handler.reportPlaying(true);
    await handler.pause();

    expect(handler.playbackState.value.playing, isFalse);
  });

  test('reanudar desde la notificación publica al momento', () async {
    // Android solo deja volver a primer plano poco después del botón.
    attach();
    await handler.play();

    expect(handler.playbackState.value.playing, isTrue);

    await handler.reportPlaying(true);
    await afterGrace();
    expect(handler.playbackState.value.playing, isTrue);
  });

  test('si tras el play la voz no llega a sonar, se deshace', () async {
    attach();
    await handler.play();
    await afterGrace();

    expect(handler.playbackState.value.playing, isFalse);
  });

  test('el ✕ pausa la voz y retira la notificación', () async {
    attach();
    await handler.reportPlaying(true);
    final states = recordStates();
    await handler.stop();

    expect(commands.calls, ['pause']);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
    expectLeavesInOneStep(await states());
  });

  test('sin libro abierto, los botones no hacen nada', () async {
    await handler.play();
    await handler.reportPlaying(true);

    expect(commands.calls, isEmpty);
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('cerrar el libro con la voz sonando la desconecta y retira la '
      'notificación', () async {
    attach();
    await handler.reportPlaying(true);
    final states = recordStates();
    await handler.detach();
    await handler.play();

    expect(handler.isAttached, isFalse);
    expect(commands.calls, isEmpty);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
    expectLeavesInOneStep(await states());
  });

  test('cerrar el libro durante el margen no deja la pausa pendiente', () async {
    attach();
    await handler.reportPlaying(true);
    await handler.reportPlaying(false);
    await handler.detach();
    await afterGrace();

    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
  });

  group('interrupciones', () {
    late StreamController<void> noisy;
    late StreamController<AudioInterruptionEvent> interruptions;

    setUp(() {
      noisy = StreamController<void>();
      interruptions = StreamController<AudioInterruptionEvent>();
      attach();
      handler.bindInterruptions(
        becomingNoisy: noisy.stream,
        interruptions: interruptions.stream,
      );
    });

    tearDown(() {
      noisy.close();
      interruptions.close();
    });

    test('desconectar los auriculares pausa la lectura', () async {
      noisy.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(commands.calls, ['pause']);
    });

    test('una llamada pausa la lectura', () async {
      interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
      await Future<void>.delayed(Duration.zero);

      expect(commands.calls, ['pause']);
    });

    test('un aviso breve que solo baja el volumen no la corta', () async {
      interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.duck));
      await Future<void>.delayed(Duration.zero);

      expect(commands.calls, isEmpty);
    });

    test('al terminar la interrupción no se reanuda sola', () async {
      interruptions
        ..add(AudioInterruptionEvent(true, AudioInterruptionType.pause))
        ..add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
      await Future<void>.delayed(Duration.zero);

      expect(commands.calls, ['pause'], reason: 'reanuda el usuario');
    });
  });
}
