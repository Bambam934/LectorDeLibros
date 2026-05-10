import 'package:fpdart/fpdart.dart';
import '../../../../core/errors/failures.dart';

abstract interface class AudioPlayerRepository {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<bool> get playingStream;
  bool get isPlaying;
  Duration? get duration;

  Future<Either<Failure, Unit>> setUrl(String url);
  Future<Either<Failure, Unit>> play();
  Future<Either<Failure, Unit>> pause();
  Future<Either<Failure, Unit>> stop();
  Future<Either<Failure, Unit>> seek(Duration position);
  Future<void> dispose();
}
