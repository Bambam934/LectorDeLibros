import 'package:just_audio/just_audio.dart';
import 'package:fpdart/fpdart.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/repositories/audio_player_repository.dart';

class JustAudioPlayerRepository implements AudioPlayerRepository {
  JustAudioPlayerRepository() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  bool get isPlaying => _player.playing;

  @override
  Duration? get duration => _player.duration;

  @override
  Future<Either<Failure, Unit>> setUrl(String url) async {
    try {
      await _player.setUrl(url);
      return right(unit);
    } catch (e) {
      return left(ServerFailure('Audio setUrl error: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> play() async {
    try {
      await _player.play();
      return right(unit);
    } catch (e) {
      return left(ServerFailure('Audio play error: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> pause() async {
    try {
      await _player.pause();
      return right(unit);
    } catch (e) {
      return left(ServerFailure('Audio pause error: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> stop() async {
    try {
      await _player.stop();
      return right(unit);
    } catch (e) {
      return left(ServerFailure('Audio stop error: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> seek(Duration position) async {
    try {
      await _player.seek(position);
      return right(unit);
    } catch (e) {
      return left(ServerFailure('Audio seek error: $e'));
    }
  }

  @override
  Future<void> dispose() async {
    await _player.dispose();
  }
}
