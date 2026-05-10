import 'package:equatable/equatable.dart';

import '../../domain/entities/chapter.dart';
import '../../domain/repositories/tts_repository.dart';

enum ReaderStatus { initial, loading, success, failure }

class ReaderState extends Equatable {
  const ReaderState({
    this.status = ReaderStatus.initial,
    this.bookId = '',
    this.chapters = const [],
    this.currentChapter,
    this.currentChapterIndex = 0,
    this.currentWordIndex = 0,
    this.progress = 0,
    this.errorMessage,
    this.ttsStatus = TtsPlaybackStatus.idle,
    this.ttsElapsed = Duration.zero,
  });

  final ReaderStatus status;
  final String bookId;
  final List<Chapter> chapters;
  final Chapter? currentChapter;
  final int currentChapterIndex;
  final int currentWordIndex;
  final double progress;
  final String? errorMessage;
  final TtsPlaybackStatus ttsStatus;
  final Duration ttsElapsed;

  int get totalChapters => chapters.length;

  bool get isTtsActive =>
      ttsStatus == TtsPlaybackStatus.playing ||
      ttsStatus == TtsPlaybackStatus.loading;

  ReaderState copyWith({
    ReaderStatus? status,
    String? bookId,
    List<Chapter>? chapters,
    Chapter? currentChapter,
    bool resetCurrentChapter = false,
    int? currentChapterIndex,
    int? currentWordIndex,
    double? progress,
    String? errorMessage,
    bool clearErrorMessage = false,
    TtsPlaybackStatus? ttsStatus,
    Duration? ttsElapsed,
  }) {
    return ReaderState(
      status: status ?? this.status,
      bookId: bookId ?? this.bookId,
      chapters: chapters ?? this.chapters,
      currentChapter: resetCurrentChapter
          ? null
          : (currentChapter ?? this.currentChapter),
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      currentWordIndex: currentWordIndex ?? this.currentWordIndex,
      progress: progress ?? this.progress,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      ttsStatus: ttsStatus ?? this.ttsStatus,
      ttsElapsed: ttsElapsed ?? this.ttsElapsed,
    );
  }

  @override
  List<Object?> get props => [
        status,
        bookId,
        chapters,
        currentChapter,
        currentChapterIndex,
        currentWordIndex,
        progress,
        errorMessage,
        ttsStatus,
        ttsElapsed,
      ];
}
