import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/sync/client_id_service.dart';
import '../../../../core/sync/sync_event.dart';
import '../../../../core/sync/sync_stream_client.dart';
import '../../data/repositories/audio_tts_repository.dart';
import '../../data/repositories/chapter_cache_repository.dart';
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
    ChapterCacheRepository? chapterCacheRepository,
    SyncStreamClient? syncStreamClient,
    ClientIdService? clientIdService,
  }) : _readerRepository = readerRepository,
       _ttsRepository = ttsRepository,
       _audioTtsRepository = audioTtsRepository,
       _chapterCache = chapterCacheRepository,
       _syncStreamClient = syncStreamClient,
       _clientIdService = clientIdService,
       super(const ReaderState()) {
    on<ReaderStarted>(_onStarted);
    on<ReaderChapterSelected>(_onChapterSelected);
    on<ReaderWordIndexChanged>(_onWordIndexChanged);
    on<ReaderProgressSaved>(_onProgressSaved);
    on<ReaderTtsToggled>(_onTtsToggled);
    on<ReaderTtsRestart>(_onTtsRestart);
    on<ReaderRemoteProgressReceived>(_onRemoteProgressReceived);
    on<ReaderRemoteProgressAccepted>(_onRemoteProgressAccepted);
    on<ReaderRemoteProgressDismissed>(_onRemoteProgressDismissed);
    on<_TtsWordIndexUpdated>(_onTtsWordIndexUpdated);
    on<_TtsStatusUpdated>(_onTtsStatusUpdated);
    on<_TtsTick>((event, emit) {
      if (_ttsStartedAt == null) return;
      final elapsed = _ttsAccumulated + DateTime.now().difference(_ttsStartedAt!);
      emit(state.copyWith(ttsElapsed: elapsed));
    });

    // Subscribe to the realtime sync channel. The subscription survives
    // for the life of the bloc; if no client is wired we silently
    // skip — keeps the bloc usable in tests and in builds where sync
    // is disabled.
    final sync = _syncStreamClient;
    if (sync != null) {
      _syncSub = sync.events.listen(_handleIncomingSyncEvent);
    }
  }

  final ReaderRepository _readerRepository;
  final TtsRepository _ttsRepository;
  final ChapterCacheRepository? _chapterCache;
  final AudioTtsRepository? _audioTtsRepository;
  final SyncStreamClient? _syncStreamClient;
  final ClientIdService? _clientIdService;
  StreamSubscription<SyncEvent>? _syncSub;

  Timer? _saveDebounceTimer;
  // Hard throttle for save-during-TTS: even if the debounce keeps
  // getting reset by continuous word emissions, this timer guarantees a
  // sync to the server at least once every 15s while TTS is active.
  // Without this, a long uninterrupted reading session would not
  // checkpoint progress until the user paused — breaking multi-device
  // resume if the app crashed mid-read.
  Timer? _forceSyncTimer;
  DateTime _lastForcedSaveAt = DateTime.fromMillisecondsSinceEpoch(0);
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

  /// Fetch chapter with offline cache fallback.
  /// Tries network first; on failure, serves from local cache.
  /// On success, caches the result for future offline use.
  Future<Chapter?> _fetchChapterWithCache(String bookId, String chapterId) async {
    final result = await _readerRepository.getChapter(
      bookId: bookId,
      chapterId: chapterId,
    );

    return result.fold(
      (failure) async {
        // Network failed — try cache.
        debugPrint('[ReaderBloc] network failed for $chapterId, trying cache');
        final cached = await _chapterCache?.getCachedChapter(chapterId);
        if (cached != null) {
          debugPrint('[ReaderBloc] serving $chapterId from cache');
        }
        return cached;
      },
      (chapter) {
        // Cache for offline use (fire-and-forget).
        _chapterCache?.cacheChapter(bookId, chapter);
        return chapter;
      },
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

        final chapterDetail = await _fetchChapterWithCache(
          event.bookId,
          selectedChapterSummary.id,
        );

        if (chapterDetail == null) {
          emit(
            state.copyWith(
              status: ReaderStatus.failure,
              errorMessage: 'No se pudo cargar el capítulo (sin conexión y sin caché)',
            ),
          );
          return;
        }

        {
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

            // FIX (web/Android no-sound regression): pre-initialise the
            // TTS engine eagerly as soon as the book opens, NOT lazily
            // on the first user tap. Web Speech API + Chrome/Safari
            // autoplay policy require `window.speechSynthesis.speak()`
            // to fire in the same synchronous chain as the user
            // gesture — if we `await initialize()` between the tap and
            // speak(), the browser silently drops the utterance. By
            // priming the engine here (and again in `_onChapterSelected`
            // below), `_onTtsToggled` can call speak() directly without
            // any await, preserving the gesture link.
            unawaited(_ensureTtsReady());
        }
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

    final chapterDetail = await _fetchChapterWithCache(
      state.bookId,
      event.chapterId,
    );

    if (chapterDetail == null) {
      emit(
        state.copyWith(
          status: ReaderStatus.failure,
          errorMessage: 'No se pudo cargar el capítulo',
        ),
      );
      return;
    }

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
  }

  Future<void> _onWordIndexChanged(
    ReaderWordIndexChanged event,
    Emitter<ReaderState> emit,
  ) async {
    final currentChapter = state.currentChapter;
    if (currentChapter == null) return;

    final maxWordIndex = _maxWordIndexForChapter(currentChapter);
    final newWordIndex = event.wordIndex.clamp(0, maxWordIndex).toInt();
    final currentIdx = state.currentWordIndex;
    final delta = (newWordIndex - currentIdx).abs();

    debugPrint('[ReaderBloc] _onWordIndexChanged — '
        'newIdx=${event.wordIndex} '
        'currentIdx=$currentIdx '
        'isTtsActive=${state.isTtsActive}');

    // Reject no-op events BEFORE touching the engine. Without this guard a
    // spurious slider onChanged carrying the current word index would still
    // call stop() and interrupt playback for no reason.
    if (newWordIndex == currentIdx) return;

    // Defensive guard against ghost-tick events emitted by the Material
    // Slider when it gets rebuilt on every tracker tick during TTS. On Web
    // and Desktop the slider occasionally fires onChanged(currentIdx ± 1)
    // or even onChanged(0) on rebuild, which used to cascade into a full
    // stop()/restart cycle ~once a second — causing the audio to chop and
    // appear desynchronised from the highlight. A real user drag emits
    // onChangeEnd with a much larger delta and goes through a different
    // path, so filtering small jitter while playing is safe.
    if (state.isTtsActive && delta <= 3) {
      debugPrint('[ReaderBloc] _onWordIndexChanged — '
          'IGNORED spurious tiny delta=$delta during TTS');
      return;
    }

    if (state.isTtsActive) {
      await _ttsRepository.stop();
    }

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
      _startForceSyncTimer();
    } else if (status == TtsPlaybackStatus.idle ||
        status == TtsPlaybackStatus.error ||
        status == TtsPlaybackStatus.completed) {
      _pauseTtsTimer();
      _stopForceSyncTimer();
      // Ensure the latest position is checkpointed when the user
      // pauses or the chapter ends — critical for multi-device sync
      // so device B picks up exactly where device A stopped.
      add(const ReaderProgressSaved());
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

  /// Force a progress save every 15s while TTS is reading, regardless
  /// of debounce activity. Prevents long uninterrupted sessions from
  /// never checkpointing to the server.
  void _startForceSyncTimer() {
    _forceSyncTimer?.cancel();
    _forceSyncTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        final now = DateTime.now();
        if (now.difference(_lastForcedSaveAt).inSeconds < 14) return;
        _lastForcedSaveAt = now;
        add(const ReaderProgressSaved());
      },
    );
  }

  void _stopForceSyncTimer() {
    _forceSyncTimer?.cancel();
    _forceSyncTimer = null;
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
        // Stamp the local write so an incoming SSE event with an
        // EARLIER lastReadAt can be safely discarded as stale.
        // Server is the actual authority on the timestamp, but the
        // local one is a tight enough lower bound — every server ts
        // for OUR write will be ≥ this value (network latency only
        // makes the server's later).
        _lastLocalSaveAtIso = DateTime.now().toUtc().toIso8601String();
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

  // ────────────────────── REMOTE SYNC HANDLERS ──────────────────────

  /// Filters incoming sync events for ones the reader cares about:
  /// `progress.updated` events that (a) originate on a different
  /// device (not our own echo), (b) target the currently-open book.
  /// Everything else is dropped silently.
  void _handleIncomingSyncEvent(SyncEvent event) {
    if (event is! SyncProgressUpdatedEvent) return;
    if (state.bookId.isEmpty || event.bookId != state.bookId) return;
    if (event.isEchoOf(_clientIdService?.cachedId)) return;
    add(ReaderRemoteProgressReceived(
      chapterId: event.chapterId,
      wordIndex: event.wordIndex,
      lastReadAt: event.lastReadAt,
    ));
  }

  void _onRemoteProgressReceived(
    ReaderRemoteProgressReceived event,
    Emitter<ReaderState> emit,
  ) {
    // Skip the remote update if it pre-dates a write we already made.
    // This guards against out-of-order delivery: two devices write
    // back-to-back, and we receive their event AFTER our local write
    // already moved the position past theirs.
    final pending = state.pendingRemoteProgress;
    if (pending != null && event.lastReadAt.compareTo(pending.lastReadAt) < 0) {
      return;
    }
    final localTs = _lastLocalSaveAtIso;
    if (localTs != null && event.lastReadAt.compareTo(localTs) < 0) {
      return;
    }
    emit(state.copyWith(
      pendingRemoteProgress: PendingRemoteProgress(
        chapterId: event.chapterId,
        wordIndex: event.wordIndex,
        lastReadAt: event.lastReadAt,
        receivedAt: DateTime.now(),
      ),
    ));
  }

  Future<void> _onRemoteProgressAccepted(
    ReaderRemoteProgressAccepted event,
    Emitter<ReaderState> emit,
  ) async {
    final pending = state.pendingRemoteProgress;
    if (pending == null) return;

    // Pause TTS first so jumping doesn't leave audio playing from the
    // old position before the highlight jumps to the new one.
    if (state.isTtsActive) {
      await _ttsRepository.stop();
    }

    final chapters = state.chapters;
    final targetChapterIdx =
        chapters.indexWhere((c) => c.id == pending.chapterId);

    // Same chapter — just move the word cursor.
    if (targetChapterIdx == state.currentChapterIndex) {
      final chapter = state.currentChapter;
      if (chapter == null) {
        emit(state.copyWith(clearPendingRemoteProgress: true));
        return;
      }
      final maxIdx = _maxWordIndexForChapter(chapter);
      final clamped = pending.wordIndex.clamp(0, maxIdx).toInt();
      emit(state.copyWith(
        currentWordIndex: clamped,
        progress: _computeBookProgress(
          chapters: chapters,
          chapterIndex: state.currentChapterIndex,
          chapterWordIndex: clamped,
        ),
        clearPendingRemoteProgress: true,
      ));
      // Mirror the accepted position back to the server so all peers
      // converge — without this, the device we accepted from would
      // still see us at the old position next time it asks.
      _saveDebounceTimer?.cancel();
      add(const ReaderProgressSaved());
      return;
    }

    // Different chapter — clear pending first so a delayed
    // `ReaderChapterSelected` handler doesn't re-trigger.
    emit(state.copyWith(clearPendingRemoteProgress: true));
    if (targetChapterIdx >= 0) {
      add(ReaderChapterSelected(pending.chapterId));
      // Defer the word-index update until the chapter has loaded.
      // `_onChapterSelected` always resets to word 0 on load, so we
      // post the real position behind it.
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (isClosed) return;
        add(ReaderWordIndexChanged(pending.wordIndex));
      });
    }
  }

  void _onRemoteProgressDismissed(
    ReaderRemoteProgressDismissed event,
    Emitter<ReaderState> emit,
  ) {
    if (state.pendingRemoteProgress == null) return;
    emit(state.copyWith(clearPendingRemoteProgress: true));
  }

  /// Server-authoritative timestamp of the last successful local save.
  /// Used to discard incoming remote updates that we already
  /// superseded. Updated in `_persistProgress`.
  String? _lastLocalSaveAtIso;

  @override
  Future<void> close() async {
    _saveDebounceTimer?.cancel();
    _forceSyncTimer?.cancel();
    _ttsElapsedTimer?.cancel();
    _ttsWordSub?.cancel();
    _ttsStatusSub?.cancel();
    await _syncSub?.cancel();
    if (state.isTtsActive) await _ttsRepository.stop();
    await _persistProgress();
    await super.close();
  }
}
