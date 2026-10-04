import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:lectorsync/core/errors/failures.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter_audio.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter_block.dart';
import 'package:lectorsync/features/reader/domain/repositories/reader_repository.dart';
import 'package:lectorsync/features/reader/domain/repositories/tts_repository.dart';
import 'package:lectorsync/features/reader/presentation/bloc/reader_bloc.dart';

class _FakeTtsRepository implements TtsRepository {
  final _wordCtrl = StreamController<int>.broadcast();
  final _statusCtrl = StreamController<TtsPlaybackStatus>.broadcast();

  int stopCalls = 0;

  @override
  Stream<int> get wordIndexStream => _wordCtrl.stream;

  @override
  Stream<TtsPlaybackStatus> get statusStream => _statusCtrl.stream;

  @override
  TtsPlaybackStatus get currentStatus => TtsPlaybackStatus.idle;

  @override
  Future<Either<Failure, Unit>> initialize() async => right(unit);

  @override
  Future<Either<Failure, Unit>> speak({
    required String text,
    required List<String> words,
    int startWordIndex = 0,
    List<ChapterBlock> blocks = const [],
  }) async => right(unit);

  @override
  Future<Either<Failure, Unit>> stop() async {
    stopCalls++;
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> setLanguage(String languageCode) async =>
      right(unit);

  @override
  Future<void> dispose() async {
    await _wordCtrl.close();
    await _statusCtrl.close();
  }
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
  }) async => left(const ServerFailure());
}

void main() {
  group('ReaderBloc.close() detiene el TTS', () {
    late _FakeTtsRepository tts;
    late ReaderBloc bloc;

    setUp(() {
      tts = _FakeTtsRepository();
      bloc = ReaderBloc(
        readerRepository: _FakeReaderRepository(),
        ttsRepository: tts,
      );
    });

    test(
      'para el motor aunque el estado del bloc no se considere activo',
      () async {
        // Este es exactamente el escenario del bug reportado: el usuario sale
        // del lector y la voz sigue sonando. El estado del bloc dice que el
        // TTS no está activo (el status llega por stream y va por detrás del
        // motor), pero el motor sí puede estar hablando.
        expect(bloc.state.isTtsActive, isFalse);

        await bloc.close();

        // Con la guarda `if (state.isTtsActive)` esto era 0 → audio zombi.
        expect(tts.stopCalls, 1);
      },
    );

    test('para el motor cuando el estado sí es activo', () async {
      bloc.emit(bloc.state.copyWith(ttsStatus: TtsPlaybackStatus.playing));
      expect(bloc.state.isTtsActive, isTrue);

      await bloc.close();

      expect(tts.stopCalls, 1);
    });
  });
}
