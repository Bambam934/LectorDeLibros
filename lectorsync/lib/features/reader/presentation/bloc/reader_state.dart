import 'package:equatable/equatable.dart';

import '../../domain/entities/chapter.dart';
import '../../domain/repositories/tts_repository.dart';

enum ReaderStatus { initial, loading, success, failure }

/// Snapshot of a remote-device update that the user has not yet
/// acknowledged. The UI watches for this field to surface a one-shot
/// "Continuando desde otro dispositivo" snackbar with an action button.
/// Cleared either when the user accepts/dismisses or when a newer
/// remote event supersedes it.
class PendingRemoteProgress extends Equatable {
  const PendingRemoteProgress({
    required this.chapterId,
    required this.wordIndex,
    required this.lastReadAt,
    required this.receivedAt,
  });

  /// Target chapter on the remote device. May differ from
  /// `state.currentChapter`, in which case accepting also navigates
  /// chapters.
  final String chapterId;
  final int wordIndex;

  /// Server-side ISO timestamp of the originating write. Used by the
  /// bloc to discard a newly-arrived update that is older than what we
  /// already applied (out-of-order delivery edge case).
  final String lastReadAt;

  /// Local time at which we received the event. Used by the snackbar to
  /// decide when to auto-dismiss after, say, 8 seconds.
  final DateTime receivedAt;

  @override
  List<Object?> get props => [chapterId, wordIndex, lastReadAt, receivedAt];
}

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
    this.pendingRemoteProgress,
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
  final PendingRemoteProgress? pendingRemoteProgress;

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
    PendingRemoteProgress? pendingRemoteProgress,
    bool clearPendingRemoteProgress = false,
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
      pendingRemoteProgress: clearPendingRemoteProgress
          ? null
          : (pendingRemoteProgress ?? this.pendingRemoteProgress),
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
        pendingRemoteProgress,
      ];
}
