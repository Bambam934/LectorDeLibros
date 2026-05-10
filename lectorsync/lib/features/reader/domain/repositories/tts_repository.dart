import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';

enum TtsPlaybackStatus { idle, loading, playing, error, completed }

abstract interface class TtsRepository {
  Stream<int> get wordIndexStream;
  Stream<TtsPlaybackStatus> get statusStream;
  TtsPlaybackStatus get currentStatus;

  Future<Either<Failure, Unit>> initialize();

  Future<Either<Failure, Unit>> speak({
    required String text,
    required List<String> words,
    int startWordIndex = 0,
  });

  Future<Either<Failure, Unit>> stop();

  Future<Either<Failure, Unit>> setLanguage(String languageCode);

  Future<void> dispose();
}
