import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:lectorsync/core/di/injection_container.dart' show TtsMode;
import 'package:lectorsync/core/errors/failures.dart';
import 'package:lectorsync/features/reader/data/repositories/audio_tts_repository.dart';
import 'package:lectorsync/features/reader/data/repositories/device_tts_repository.dart';
import 'package:lectorsync/features/reader/data/repositories/tts_repository_proxy.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter_block.dart';
import 'package:lectorsync/features/reader/domain/repositories/tts_repository.dart';

/// Motor del dispositivo que, como el real, publica `idle` al parar.
class _FakeDevice extends Fake implements DeviceTtsRepository {
  final words = StreamController<int>.broadcast(sync: true);
  final status = StreamController<TtsPlaybackStatus>.broadcast(sync: true);
  final _recovery = StreamController<void>.broadcast();

  /// Palabra que el motor aún publica mientras para.
  int? lateWord;

  @override
  Stream<int> get wordIndexStream => words.stream;

  @override
  Stream<TtsPlaybackStatus> get statusStream => status.stream;

  @override
  Stream<void> get recoveryStream => _recovery.stream;

  @override
  Future<Either<Failure, Unit>> stop() async {
    final late = lateWord;
    if (late != null) words.add(late);
    status.add(TtsPlaybackStatus.idle);
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> speak({
    required String text,
    required List<String> words,
    int startWordIndex = 0,
    List<ChapterBlock> blocks = const [],
  }) async =>
      right(unit);
}

class _FakeAudio extends Fake implements AudioTtsRepository {}

void main() {
  late _FakeDevice device;
  late TtsRepositoryProxy proxy;
  late List<int> published;

  setUp(() {
    device = _FakeDevice();
    proxy = TtsRepositoryProxy(
      device: device,
      audio: _FakeAudio(),
      initialMode: TtsMode.device,
    );
    published = [];
    proxy.wordIndexStream.listen(published.add);
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 40));

  test('al parar no publica la palabra que quedaba pendiente', () async {
    device.words
      ..add(100)
      ..add(101); // Dentro de los 16 ms: queda pendiente.
    await proxy.stop();
    await settle();

    expect(published, isNot(contains(101)));
  });

  test('lo que el motor publica mientras para no pisa el salto', () async {
    device.words.add(1869);
    await settle();
    device.lateWord = 1870;

    await proxy.stop();
    await proxy.speak(text: 'x', words: const ['x'], startWordIndex: 1575);
    device.words.add(1575);
    await settle();

    expect(published, [1869, 1575]);
  });

  test('tras volver a hablar sigue publicando con normalidad', () async {
    await proxy.stop();
    await proxy.speak(text: 'x', words: const ['x']);
    device.words.add(5);
    await settle();
    device.words.add(6);
    await settle();

    expect(published, [5, 6]);
  });
}
