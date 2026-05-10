import 'dart:async';
import 'package:fpdart/fpdart.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/chapter_audio.dart';
import '../../domain/repositories/audio_player_repository.dart';
import '../../domain/repositories/reader_repository.dart';
import '../../domain/repositories/tts_repository.dart';

class AudioTtsRepository implements TtsRepository {
  AudioTtsRepository({
    required AudioPlayerRepository audioPlayer,
    required ReaderRepository readerRepository,
    required String Function() baseUrlGetter,
  })  : _audioPlayer = audioPlayer,
        _readerRepository = readerRepository,
        _baseUrlGetter = baseUrlGetter;

  final AudioPlayerRepository _audioPlayer;
  final ReaderRepository _readerRepository;
  final String Function() _baseUrlGetter;

  final StreamController<int> _wordIndexController =
      StreamController<int>.broadcast();
  final StreamController<TtsPlaybackStatus> _statusController =
      StreamController<TtsPlaybackStatus>.broadcast();

  TtsPlaybackStatus _currentStatus = TtsPlaybackStatus.idle;
  List<WordTimestamp> _wordTimestamps = [];
  int _lastEmittedWordIndex = -1;
  String? _currentBookId;
  String? _currentChapterId;
  String _voiceId = '21m00Tcm4TlvDq8ikWAW';

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;

  @override
  Stream<int> get wordIndexStream => _wordIndexController.stream;

  @override
  Stream<TtsPlaybackStatus> get statusStream => _statusController.stream;

  @override
  TtsPlaybackStatus get currentStatus => _currentStatus;

  @override
  Future<Either<Failure, Unit>> initialize() async {
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> speak({
    required String text,
    required List<String> words,
    int startWordIndex = 0,
  }) async {
    if (_currentBookId == null || _currentChapterId == null) {
      return left(const ServerFailure('No book/chapter context set.'));
    }

    try {
      _emit(TtsPlaybackStatus.loading);

      final result = await _readerRepository.getChapterAudio(
        bookId: _currentBookId!,
        chapterId: _currentChapterId!,
        voiceId: _voiceId,
        provider: 'elevenlabs',
      );

      return result.fold(
        (failure) {
          _emit(TtsPlaybackStatus.error);
          return left(failure);
        },
        (chapterAudio) async {
          _wordTimestamps = chapterAudio.wordTimestamps;
          _lastEmittedWordIndex = -1;

          if (!chapterAudio.hasAudio) {
            _emit(TtsPlaybackStatus.error);
            return left(const ServerFailure('No audio URL available.'));
          }

          final audioUrl = _resolveAudioUrl(chapterAudio.audioUrl!);
          final setUrlResult = await _audioPlayer.setUrl(audioUrl);

          return setUrlResult.fold(
            (failure) {
              _emit(TtsPlaybackStatus.error);
              return left(failure);
            },
            (_) async {
              _startPositionListener();

              if (startWordIndex > 0 && _wordTimestamps.isNotEmpty) {
                final seekMs = _findTimestampForWord(startWordIndex);
                if (seekMs > 0) {
                  await _audioPlayer.seek(Duration(milliseconds: seekMs));
                }
              }

              final playResult = await _audioPlayer.play();
              playResult.fold(
                (failure) {
                  _emit(TtsPlaybackStatus.error);
                },
                (_) {},
              );
              return playResult;
            },
          );
        },
      );
    } catch (e) {
      _emit(TtsPlaybackStatus.error);
      return left(ServerFailure('AudioTts speak error: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> stop() async {
    _positionSub?.cancel();
    _positionSub = null;
    _playingSub?.cancel();
    _playingSub = null;
    _lastEmittedWordIndex = -1;
    _wordTimestamps = [];

    final result = await _audioPlayer.stop();
    _emit(TtsPlaybackStatus.idle);
    return result;
  }

  @override
  Future<Either<Failure, Unit>> setLanguage(String languageCode) async {
    return right(unit);
  }

  @override
  Future<void> dispose() async {
    _positionSub?.cancel();
    _playingSub?.cancel();
    await _audioPlayer.dispose();
    await _wordIndexController.close();
    await _statusController.close();
  }

  void setContext({required String bookId, required String chapterId}) {
    _currentBookId = bookId;
    _currentChapterId = chapterId;
  }

  void setVoiceId(String voiceId) => _voiceId = voiceId;

  void _emit(TtsPlaybackStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _startPositionListener() {
    _positionSub?.cancel();
    _playingSub?.cancel();

    _positionSub = _audioPlayer.positionStream.listen((position) {
      _onPositionUpdate(position.inMilliseconds);
    });

    _playingSub = _audioPlayer.playingStream.listen((isPlaying) {
      if (!isPlaying && _currentStatus == TtsPlaybackStatus.playing) {
        _emit(TtsPlaybackStatus.completed);
      } else if (isPlaying && _currentStatus != TtsPlaybackStatus.playing) {
        _emit(TtsPlaybackStatus.playing);
      }
    });
  }

  void _onPositionUpdate(int positionMs) {
    if (_wordTimestamps.isEmpty) return;
    if (_wordIndexController.isClosed) return;

    final wordIndex = _findWordAtPosition(positionMs);
    if (wordIndex != _lastEmittedWordIndex) {
      _lastEmittedWordIndex = wordIndex;
      _wordIndexController.add(wordIndex);
    }
  }

  int _findWordAtPosition(int positionMs) {
    if (_wordTimestamps.isEmpty) return 0;

    int lo = 0;
    int hi = _wordTimestamps.length - 1;
    int result = 0;

    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (_wordTimestamps[mid].timestampMs <= positionMs) {
        result = _wordTimestamps[mid].wordIndex;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }

    return result;
  }

  int _findTimestampForWord(int wordIndex) {
    if (_wordTimestamps.isEmpty) return 0;

    for (final ts in _wordTimestamps) {
      if (ts.wordIndex >= wordIndex) {
        return ts.timestampMs;
      }
    }
    return 0;
  }

  String _resolveAudioUrl(String audioPath) {
    if (audioPath.startsWith('http')) return audioPath;
    final base = _baseUrlGetter();
    final separator = base.endsWith('/') ? '' : '/';
    return '$base$separator$audioPath';
  }
}
