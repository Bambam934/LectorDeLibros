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
    handler = ReadingAudioHandler();
    commands = _FakeCommands();
  });

  void attach() => handler.attach(
        bookId: 'b1',
        bookTitle: 'Cálculo integral',
        commands: commands,
      );

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

  test('y que está en pausa, con el botón de reanudar', () async {
    attach();
    await handler.reportPlaying(true);
    await handler.reportPlaying(false);

    final state = handler.playbackState.value;
    expect(state.playing, isFalse);
    expect(state.controls.first, MediaControl.play);
  });

  test('los botones del sistema llegan al lector', () async {
    attach();
    await handler.play();
    await handler.pause();

    expect(commands.calls, ['play', 'pause']);
  });

  test('el ✕ pausa la voz y retira la notificación', () async {
    attach();
    await handler.reportPlaying(true);
    await handler.stop();

    expect(commands.calls, ['pause']);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
  });

  test('sin libro abierto, los botones no hacen nada', () async {
    await handler.play();
    await handler.reportPlaying(true);

    expect(commands.calls, isEmpty);
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('cerrar el libro desconecta y retira la notificación', () async {
    attach();
    await handler.reportPlaying(true);
    await handler.detach();
    await handler.play();

    expect(handler.isAttached, isFalse);
    expect(commands.calls, isEmpty);
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
