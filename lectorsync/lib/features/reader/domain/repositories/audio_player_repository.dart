import 'package:fpdart/fpdart.dart';
import '../../../../core/errors/failures.dart';

abstract interface class AudioPlayerRepository {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<bool> get playingStream;

  /// Emite cuando el audio llega al final. No se puede deducir de
  /// [playingStream]: en just_audio `playing` sigue en true al terminar.
  Stream<void> get completedStream;
  bool get isPlaying;
  Duration? get duration;

  Future<Either<Failure, Unit>> setUrl(String url);
  Future<Either<Failure, Unit>> play();
  Future<Either<Failure, Unit>> pause();
  Future<Either<Failure, Unit>> stop();
  Future<Either<Failure, Unit>> seek(Duration position);
  Future<void> dispose();
}
