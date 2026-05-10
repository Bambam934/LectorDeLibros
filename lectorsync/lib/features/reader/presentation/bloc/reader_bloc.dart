import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/audio_tts_repository.dart';
import '../../domain/entities/chapter.dart';
import '../../domain/repositories/reader_repository.dart';
import '../../domain/repositories/tts_repository.dart';
import 'reader_event.dart';
import 'reader_state.dart';

// Internal events — only dispatched by this file via stream subscriptions.
class _TtsWordIndexUpdated extends ReaderEvent {
  const _TtsWordIndexUpdated(this.wordIndex);
  final int wordIndex;
  @override
  List<Object?> get props => [wordIndex];
}

class _TtsStatusUpdated extends ReaderEvent {
  const _TtsStatusUpdated(this.status);
  final TtsPlaybackStatus status;
  @override
  List<Object?> get props => [status];
}

class _TtsTick extends ReaderEvent {
  const _TtsTick();
  @override
  List<Object?> get props => [];
}

class ReaderBloc extends Bloc<ReaderEvent, ReaderState> {
  ReaderBloc({
    required ReaderRepository readerRepository,
    required TtsRepository ttsRepository,
    AudioTtsRepository? audioTtsRepository,
  }) : _readerRepository = readerRepository,
       _ttsRepository = ttsRepository,
       _audioTtsRepository = audioTtsRepository,
       super(const ReaderState()) {
    on<ReaderStarted>(_onStarted);
    on<ReaderChapterSelected>(_onChapterSelected);
    on<ReaderWordIndexChanged>(_onWordIndexChanged);
    on<ReaderProgressSaved>(_onProgressSaved);
    on<ReaderTtsToggled>(_onTtsToggled);
    on<ReaderTtsRestart>(_onTtsRestart);
    on<_TtsWordIndexUpdated>(_onTtsWordIndexUpdated);
    on<_TtsStatusUpdated>(_onTtsStatusUpdated);
    on<_TtsTick>((event, emit) {
      if (_ttsStartedAt == null) return;
      final elapsed = _ttsAccumulated + DateTime.now().difference(_ttsStartedAt!);
      emit(state.copyWith(ttsElapsed: elapsed));
    });
  }

  final ReaderRepository _readerRepository;
  final TtsRepository _ttsRepository;
  final AudioTtsRepository? _audioTtsRepository;

  Timer? _saveDebounceTimer;
  String? _lastSavedChapterId;
  int? _lastSavedGlobalWordIndex;
  StreamSubscription<int>? _ttsWordSub;
  StreamSubscription<TtsPlaybackStatus>? _ttsStatusSub;

  Timer? _ttsElapsedTimer;
  DateTime? _ttsStartedAt;
  Duration _ttsAccumulated = Duration.zero;

  /// Cached total word count across all chapters — recomputed only when
  /// the chapter list changes (not on every word update).
  int _cachedTotalWords = 0;
  bool _ttsReady = false;

  @override
  void onChange(Change<ReaderState> change) {
    super.onChange(change);
    // Diagnostic: log unexpected jumps in currentWordIndex (delta > 25)
    // to identify the path that mutates word index outside the slider
    // and TTS-progress flows.
    final prevIdx = change.currentState.currentWordIndex;
    final newIdx = change.nextState.currentWordIndex;
    if (prevIdx != newIdx && (newIdx - prevIdx).abs() > 25) {
      debugPrint('[ReaderBloc] state.currentWordIndex JUMP — '
          '$prevIdx → $newIdx');
    }
  }

  Future<void> _ensureTtsReady() async {
    if (_ttsReady) return;
    _ttsReady = true;
    await _ttsRepository.initialize();
    _ttsWordSub = _ttsRepository.wordIndexStream.listen(
      (idx) => add(_TtsWordIndexUpdated(idx)),
    );
    _ttsStatusSub = _ttsRepository.statusStream.listen(
      (s) => add(_TtsStatusUpdated(s)),
    );
  }

  Future<void> _onStarted(
    ReaderStarted event,
    Emitter<ReaderState> emit,
  ) async {
    emit(
      state.copyWith(
        status: ReaderStatus.loading,
        bookId: event.bookId,
        clearErrorMessage: true,
      ),
    );

    final chaptersResult = await _readerRepository.getChapters(event.bookId);

    await chaptersResult.fold(
      (failure) async {
        emit(
          state.copyWith(
            status: ReaderStatus.failure,
            errorMessage: failure.message,
          ),
        );
      },
      (chapters) async {
        if (chapters.isEmpty) {
          emit(
            state.copyWith(
              status: ReaderStatus.success,
              chapters: const [],
              resetCurrentChapter: true,
              currentChapterIndex: 0,
              currentWordIndex: 0,
              progress: 0,
            ),
          );
          return;
        }

        // Cache total words once when chapters are loaded.
        _cachedTotalWords = chapters.fold<int>(
          0, (sum, c) => sum + _effectiveWordCount(c),
        );

        final selectedIndex = _resolveInitialChapterIndex(
          chapters: chapters,
          initialChapterId: event.initialChapterId,
        );

        final selectedChapterSummary = chapters[selectedIndex];

        final chapterResult = await _readerRepository.getChapter(
          bookId: event.bookId,
          chapterId: selectedChapterSummary.id,
        );

        chapterResult.fold(
          (failure) {
            emit(
              state.copyWith(
                status: ReaderStatus.failure,
                errorMessage: failure.message,
              ),
            );
          },
          (chapterDetail) {
            final localWordIndex = _toLocalWordIndex(
              chapters: chapters,
              chapterIndex: selectedIndex,
              globalWordIndex: event.initialWordIndex,
              currentChapterMaxWordIndex: _maxWordIndexForChapter(
                chapterDetail,
              ),
            );

            emit(
              state.copyWith(
                status: ReaderStatus.success,
                bookId: event.bookId,
                chapters: chapters,
                currentChapter: chapterDetail,
                currentChapterIndex: selectedIndex,
                currentWordIndex: localWordIndex,
                progress: _computeBookProgress(
                  chapters: chapters,
                  chapterIndex: selectedIndex,
                  chapterWordIndex: localWordIndex,
                ),
                clearErrorMessage: true,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _onChapterSelected(
    ReaderChapterSelected event,
    Emitter<ReaderState> emit,
  ) async {
    final chapters = state.chapters;
    if (chapters.isEmpty || state.bookId.isEmpty) return;

    final targetIndex = chapters.indexWhere((c) => c.id == event.chapterId);
    if (targetIndex < 0 || targetIndex == state.currentChapterIndex) return;

    debugPrint('[ReaderBloc] _onChapterSelected — '
        'chapterId=${event.chapterId} '
        'autoPlayTts=${event.autoPlayTts} '
        'currentIdx=${state.currentChapterIndex}→$targetIndex');

    // Stop TTS before switching chapter.
    if (state.isTtsActive) await _ttsRepository.stop();
    _resetTtsTimer();

    await _persistProgress();

    emit(state.copyWith(status: ReaderStatus.loading, clearErrorMessage: true));

    final chapterResult = await _readerRepository.getChapter(
      bookId: state.bookId,
      chapterId: event.chapterId,
    );

    chapterResult.fold(
      (failure) {
        emit(
          state.copyWith(
            status: ReaderStatus.failure,
            errorMessage: failure.message,
          ),
        );
      },
      (chapterDetail) {
        emit(
          state.copyWith(
            status: ReaderStatus.success,
            currentChapter: chapterDetail,
            currentChapterIndex: targetIndex,
            currentWordIndex: 0,
            progress: _computeBookProgress(
              chapters: chapters,
              chapterIndex: targetIndex,
              chapterWordIndex: 0,
            ),
            clearErrorMessage: true,
          ),
        );
        add(const ReaderProgressSaved());
        if (event.autoPlayTts) {
          add(const ReaderTtsToggled());
        }
      },
    );
  }

  Future<void> _onWordIndexChanged(
    ReaderWordIndexChanged event,
    Emitter<ReaderState> emit,
  ) async {
    final currentChapter = state.currentChapter;
    if (currentChapter == null) return;

    debugPrint('[ReaderBloc] _onWordIndexChanged — '
        'newIdx=${event.wordIndex} '
        'currentIdx=${state.currentWordIndex} '
        'isTtsActive=${state.isTtsActive}');
    if (state.isTtsActive) {
      await _ttsRepository.stop();
    }

    final maxWordIndex = _maxWordIndexForChapter(currentChapter);
    final newWordIndex = event.wordIndex.clamp(0, maxWordIndex).toInt();

    if (newWordIndex == state.currentWordIndex) return;

    emit(
      state.copyWith(
        currentWordIndex: newWordIndex,
        progress: _computeBookProgress(
          chapters: state.chapters,
          chapterIndex: state.currentChapterIndex,
          chapterWordIndex: newWordIndex,
        ),
      ),
    );

    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(
      const Duration(milliseconds: 700),
      () => add(const ReaderProgressSaved()),
    );
  }

  Future<void> _onProgressSaved(
    ReaderProgressSaved event,
    Emitter<ReaderState> emit,
  ) async {
    await _persistProgress(emit: emit);
  }

  Future<void> _onTtsToggled(
    ReaderTtsToggled event,
    Emitter<ReaderState> emit,
  ) async {
    final chapter = state.currentChapter;
    if (chapter == null) return;

    debugPrint('[ReaderBloc] _onTtsToggled — '
        'isTtsActive=${state.isTtsActive} wordIdx=${state.currentWordIndex}');
    if (state.isTtsActive) {
      await _ttsRepository.stop();
    } else {
      final text = chapter.text ?? '';
      final words = chapter.words;
      if (words.isEmpty) return;

      await _ensureTtsReady();

      _audioTtsRepository?.setContext(
        bookId: state.bookId,
        chapterId: chapter.id,
      );

      await _ttsRepository.speak(
        text: text,
        words: words,
        startWordIndex: state.currentWordIndex,
      );
    }
  }

  Future<void> _onTtsRestart(
    ReaderTtsRestart event,
    Emitter<ReaderState> emit,
  ) async {
    final chapter = state.currentChapter;
    if (chapter == null) return;
    final words = chapter.words;
    if (words.isEmpty) return;

    debugPrint('[ReaderBloc] _onTtsRestart — '
        'wordIdx=${state.currentWordIndex}');
    await _ttsRepository.stop();
    await _ensureTtsReady();

    _audioTtsRepository?.setContext(
      bookId: state.bookId,
      chapterId: chapter.id,
    );

    await _ttsRepository.speak(
      text: chapter.text ?? '',
      words: words,
      startWordIndex: state.currentWordIndex,
    );
  }

  void _onTtsWordIndexUpdated(
    _TtsWordIndexUpdated event,
    Emitter<ReaderState> emit,
  ) {
    final chapter = state.currentChapter;
    if (chapter == null) return;

    final maxIdx = _maxWordIndexForChapter(chapter);
    final clamped = event.wordIndex.clamp(0, maxIdx).toInt();
    if (clamped == state.currentWordIndex) return;
    // Only log "unusual" jumps (delta > 25 words) to avoid log spam.
    final delta = (clamped - state.currentWordIndex).abs();
    if (delta > 25) {
      debugPrint('[ReaderBloc] _onTtsWordIndexUpdated JUMP — '
          '${state.currentWordIndex} → $clamped (raw=${event.wordIndex})');
    }

    emit(
      state.copyWith(
        currentWordIndex: clamped,
        progress: _computeBookProgress(
          chapters: state.chapters,
          chapterIndex: state.currentChapterIndex,
          chapterWordIndex: clamped,
        ),
      ),
    );

    // Save progress with a longer debounce during TTS to reduce write frequency.
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(
      const Duration(seconds: 2),
      () => add(const ReaderProgressSaved()),
    );
  }

  void _onTtsStatusUpdated(
    _TtsStatusUpdated event,
    Emitter<ReaderState> emit,
  ) {
    final status = event.status;

    if (status == TtsPlaybackStatus.playing) {
      _startTtsTimer();
    } else if (status == TtsPlaybackStatus.idle ||
        status == TtsPlaybackStatus.error ||
        status == TtsPlaybackStatus.completed) {
      _pauseTtsTimer();
    }

    if (status == TtsPlaybackStatus.completed) {
      _resetTtsTimer();
      emit(state.copyWith(
        ttsStatus: TtsPlaybackStatus.idle,
        ttsElapsed: Duration.zero,
      ));
      _onChapterCompleted(emit);
    } else {
      emit(state.copyWith(ttsStatus: status));
    }
  }

  void _startTtsTimer() {
    _ttsStartedAt = DateTime.now();
    _ttsElapsedTimer?.cancel();
    _ttsElapsedTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => add(const _TtsTick()),
    );
  }

  void _pauseTtsTimer() {
    if (_ttsStartedAt != null) {
      _ttsAccumulated += DateTime.now().difference(_ttsStartedAt!);
      _ttsStartedAt = null;
    }
    _ttsElapsedTimer?.cancel();
    _ttsElapsedTimer = null;
  }

  void _resetTtsTimer() {
    _ttsElapsedTimer?.cancel();
    _ttsElapsedTimer = null;
    _ttsStartedAt = null;
    _ttsAccumulated = Duration.zero;
  }

  void _onChapterCompleted(Emitter<ReaderState> emit) {
    final chapters = state.chapters;
    final nextIndex = state.currentChapterIndex + 1;
    if (nextIndex >= chapters.length) return;

    final nextChapterId = chapters[nextIndex].id;
    add(ReaderChapterSelected(nextChapterId, autoPlayTts: true));
  }

  Future<void> _persistProgress({Emitter<ReaderState>? emit}) async {
    final bookId = state.bookId;
    final currentChapter = state.currentChapter;

    if (bookId.isEmpty || currentChapter == null || state.chapters.isEmpty) {
      return;
    }

    final globalWordIndex = _toGlobalWordIndex(
      chapters: state.chapters,
      chapterIndex: state.currentChapterIndex,
      chapterWordIndex: state.currentWordIndex,
    );

    if (_lastSavedChapterId == currentChapter.id &&
        _lastSavedGlobalWordIndex == globalWordIndex) {
      return;
    }

    final result = await _readerRepository.saveProgress(
      bookId: bookId,
      chapterId: currentChapter.id,
      wordIndex: globalWordIndex,
    );

    result.fold(
      (failure) {
        if (emit != null) {
          emit(state.copyWith(errorMessage: failure.message));
        }
      },
      (_) {
        _lastSavedChapterId = currentChapter.id;
        _lastSavedGlobalWordIndex = globalWordIndex;
      },
    );
  }

  int _resolveInitialChapterIndex({
    required List<Chapter> chapters,
    required String? initialChapterId,
  }) {
    if (initialChapterId == null) return 0;
    final index = chapters.indexWhere((c) => c.id == initialChapterId);
    return index < 0 ? 0 : index;
  }

  int _toLocalWordIndex({
    required List<Chapter> chapters,
    required int chapterIndex,
    required int globalWordIndex,
    required int currentChapterMaxWordIndex,
  }) {
    if (globalWordIndex <= 0) return 0;
    final wordsBefore = _wordsBeforeChapter(chapters, chapterIndex);
    final localWordIndex = globalWordIndex - wordsBefore;
    return localWordIndex.clamp(0, currentChapterMaxWordIndex).toInt();
  }

  int _toGlobalWordIndex({
    required List<Chapter> chapters,
    required int chapterIndex,
    required int chapterWordIndex,
  }) {
    return _wordsBeforeChapter(chapters, chapterIndex) + chapterWordIndex;
  }

  int _wordsBeforeChapter(List<Chapter> chapters, int chapterIndex) {
    var sum = 0;
    for (var i = 0; i < chapterIndex; i++) {
      sum += _effectiveWordCount(chapters[i]);
    }
    return sum;
  }

  int _effectiveWordCount(Chapter chapter) {
    if (chapter.words.isNotEmpty) return chapter.words.length;
    return chapter.wordCount;
  }

  int _maxWordIndexForChapter(Chapter chapter) {
    final wordCount = _effectiveWordCount(chapter);
    return wordCount < 0 ? 0 : wordCount;
  }

  double _computeBookProgress({
    required List<Chapter> chapters,
    required int chapterIndex,
    required int chapterWordIndex,
  }) {
    if (chapters.isEmpty) return 0;

    // Use cached total — avoids O(n) fold on every word update.
    final totalWords = _cachedTotalWords;

    if (totalWords <= 0) {
      if (chapters.length == 1) return 0;
      return (chapterIndex / (chapters.length - 1)).clamp(0, 1).toDouble();
    }

    final globalWordIndex = _toGlobalWordIndex(
      chapters: chapters,
      chapterIndex: chapterIndex,
      chapterWordIndex: chapterWordIndex,
    );

    return (globalWordIndex / totalWords).clamp(0, 1).toDouble();
  }

  @override
  Future<void> close() async {
    _saveDebounceTimer?.cancel();
    _ttsElapsedTimer?.cancel();
    _ttsWordSub?.cancel();
    _ttsStatusSub?.cancel();
    if (state.isTtsActive) await _ttsRepository.stop();
    await _persistProgress();
    await super.close();
  }
}
