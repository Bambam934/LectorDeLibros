import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:lectorsync/core/errors/failures.dart';
import 'package:lectorsync/features/reader/data/repositories/audio_tts_repository.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter_audio.dart';
import 'package:lectorsync/features/reader/domain/repositories/audio_player_repository.dart';
import 'package:lectorsync/features/reader/domain/repositories/reader_repository.dart';
import 'package:lectorsync/features/reader/domain/repositories/tts_repository.dart';

/// Se comporta como just_audio: `play()` pone `playing` en true y al llegar
/// al final NO lo vuelve a false; el final llega por [completed].
class _FakePlayer implements AudioPlayerRepository {
  final playing = StreamController<bool>.broadcast();
  final completed = StreamController<void>.broadcast();

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();

  @override
  Stream<bool> get playingStream => playing.stream;

  @override
  Stream<void> get completedStream => completed.stream;

  @override
  bool get isPlaying => false;

  @override
  Duration? get duration => null;

  @override
  Future<Either<Failure, Unit>> setUrl(String url) async => right(unit);

  @override
  Future<Either<Failure, Unit>> play() async {
    playing.add(true);
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> pause() async => right(unit);

  @override
  Future<Either<Failure, Unit>> stop() async => right(unit);

  @override
  Future<Either<Failure, Unit>> seek(Duration position) async => right(unit);

  @override
  Future<void> dispose() async {}
}

class _FakeReaderRepository implements ReaderRepository {
  @override
  Future<Either<Failure, List<Chapter>>> getChapters(String bookId) async =>
      right(const []);

  @override
  Future<Either<Failure, Chapter>> getChapter({
    required String bookId,
    required String chapterId,
  }) async => left(const CacheFailure());

  @override
  Future<Either<Failure, bool>> saveProgress({
    required String bookId,
    required String chapterId,
    required int wordIndex,
  }) async => right(true);

  @override
  Future<Either<Failure, ChapterAudio>> getChapterAudio({
    required String bookId,
    required String chapterId,
    String voiceId = '21m00Tcm4TlvDq8ikWAW',
    String provider = 'mock',
  }) async => right(
        ChapterAudio(
          chapterId: chapterId,
          provider: provider,
          audioUrl: 'https://audio.test/$chapterId.mp3',
        ),
      );
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _FakePlayer player;
  late AudioTtsRepository repo;

  setUp(() {
    player = _FakePlayer();
    repo = AudioTtsRepository(
      audioPlayer: player,
      readerRepository: _FakeReaderRepository(),
      baseUrlGetter: () => 'https://api.test',
    )..setContext(bookId: 'libro', chapterId: 'c1');
  });

  test('el final del audio emite completed aunque playing siga en true',
      () async {
    await repo.speak(text: 'hola mundo', words: const ['hola', 'mundo']);
    await _settle();
    expect(repo.currentStatus, TtsPlaybackStatus.playing);

    player.completed.add(null);
    await _settle();

    // Sin `completed` el lector no pasa solo al capítulo siguiente.
    expect(repo.currentStatus, TtsPlaybackStatus.completed);
  });

  test('un final que llega sin estar leyendo no cuenta como fin de capítulo',
      () async {
    await repo.speak(text: 'hola mundo', words: const ['hola', 'mundo']);
    await _settle();
    await repo.stop();

    player.completed.add(null);
    await _settle();

    expect(repo.currentStatus, TtsPlaybackStatus.idle);
  });
}
