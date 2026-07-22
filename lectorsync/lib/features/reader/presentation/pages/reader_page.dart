import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../../core/sync/client_id_service.dart';
import '../../../../core/sync/sync_stream_client.dart';
import '../../../../core/utils/haptics.dart';
import '../../../settings/domain/entities/reading_preferences.dart';
import '../../../settings/presentation/cubit/preferences_cubit.dart';
import '../../../settings/presentation/widgets/reading_customization_sheet.dart';
import '../../data/repositories/audio_tts_repository.dart';
import '../../data/repositories/device_tts_repository.dart';
import '../../data/repositories/tts/tts_capabilities.dart';
import '../../data/repositories/tts_repository_proxy.dart';
import '../../domain/repositories/tts_repository.dart';
import '../../data/repositories/bookmark_repository.dart';
import '../../data/repositories/chapter_cache_repository.dart';
import '../../data/repositories/reading_stats_repository.dart';
import '../../domain/entities/bookmark.dart';
import '../../domain/repositories/reader_repository.dart';
import '../bloc/reader_bloc.dart';
import '../bloc/reader_event.dart';
import '../bloc/reader_state.dart';
import '../widgets/ambient_sound_sheet.dart';
import '../widgets/book_search_delegate.dart';
import '../widgets/bookmarks_sheet.dart';
import '../widgets/reading_stats_sheet.dart';

class ReaderPage extends StatelessWidget {
  const ReaderPage({
    required this.bookId,
    required this.bookTitle,
    this.initialChapterId,
    this.initialWordIndex = 0,
    super.key,
  });

  final String bookId;
  final String bookTitle;
  final String? initialChapterId;
  final int initialWordIndex;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          ReaderBloc(
            readerRepository: sl(),
            ttsRepository: sl(),
            audioTtsRepository: sl.isRegistered<AudioTtsRepository>()
                ? sl<AudioTtsRepository>()
                : null,
            chapterCacheRepository: sl.isRegistered<ChapterCacheRepository>()
                ? sl<ChapterCacheRepository>()
                : null,
            // Realtime sync is opt-in via DI: registered in
            // injection_container.dart only when the app is online and
            // logged in. Tests / offline-only builds skip the registration
            // and the bloc gracefully no-ops on the sync side.
            syncStreamClient: sl.isRegistered<SyncStreamClient>()
                ? sl<SyncStreamClient>()
                : null,
            clientIdService: sl.isRegistered<ClientIdService>()
                ? sl<ClientIdService>()
                : null,
          )..add(
            ReaderStarted(
              bookId,
              initialChapterId: initialChapterId,
              initialWordIndex: initialWordIndex,
            ),
          ),
      child: _ReaderView(bookTitle: bookTitle),
    );
  }
}

class _ReaderView extends StatefulWidget {
  const _ReaderView({required this.bookTitle});

  final String bookTitle;

  @override
  State<_ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<_ReaderView> with WidgetsBindingObserver {
  ScrollController? _scrollController;
  List<GlobalKey> _paragraphKeys = [];
  List<int> _wordOffsets = [];
  int _lastScrolledParagraphIndex = -1;
  String? _lastChapterId;
  bool _immersive = false;
  bool _tocVisible = false;
  bool _isEstimatingProgress = false;
  bool _speedBarVisible = false;
  StreamSubscription<bool>? _estimatingSub;

  // Auto-scroll "seguir la voz": cuando el usuario hace scroll manual
  // durante la reproducción, desenganchamos (dejamos de arrastrar la vista)
  // y mostramos un botón "Volver a la lectura" que vuelve a engancharlo.
  final ValueNotifier<bool> _followVoice = ValueNotifier<bool>(true);
  bool _showReturnButton = false;
  bool _streamsSubscribed = false;
  bool _disposed = false;

  // Reading session tracking.
  final Stopwatch _sessionStopwatch = Stopwatch();
  int _sessionStartWordIndex = 0;
  StreamSubscription<TtsPlaybackStatus>? _ttsStatusSub;

  late final PreferencesCubit _preferencesCubit = PreferencesCubit(
    repository: sl(),
  );

  void _toggleImmersive() => setState(() => _immersive = !_immersive);
  void _toggleToc() => setState(() => _tocVisible = !_tocVisible);
  void _toggleSpeedBar() =>
      setState(() => _speedBarVisible = !_speedBarVisible);

  void _openCustomizationSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: _preferencesCubit,
        child: const ReadingCustomizationSheet(),
      ),
    );
  }

  void _openVoiceMenu() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => BlocProvider.value(
        value: context.read<ReaderBloc>(),
        child: const _VoiceMenuSheet(),
      ),
    );
  }

  /// Internal: add bookmark without showing a snackbar (called from
  /// inside the bookmarks sheet via the "Aquí" button).
  Bookmark? _buildCurrentBookmark() {
    final state = context.read<ReaderBloc>().state;
    final chapter = state.currentChapter;
    if (chapter == null) return null;

    final wordIdx = state.currentWordIndex;
    final words = chapter.words;
    final snippetStart = (wordIdx - 5).clamp(0, words.length);
    final snippetEnd = (wordIdx + 5).clamp(0, words.length);
    final snippet = words.sublist(snippetStart, snippetEnd).join(' ');

    return Bookmark(
      id: '${chapter.id}_${wordIdx}_${DateTime.now().millisecondsSinceEpoch}',
      bookId: state.bookId,
      chapterId: chapter.id,
      chapterTitle: chapter.title,
      wordIndex: wordIdx,
      snippet: snippet,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _addBookmarkAtCurrent() async {
    final bookmark = _buildCurrentBookmark();
    if (bookmark == null) return;
    Haptics.medium();
    await sl<BookmarkRepository>().addBookmark(bookmark);
  }

  void _openBookmarks(BuildContext context) {
    final state = context.read<ReaderBloc>().state;
    final hasChapter = state.currentChapter != null;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BookmarksSheet(
        bookId: state.bookId,
        canAddCurrent: hasChapter,
        onAddCurrent: hasChapter ? _addBookmarkAtCurrent : null,
        onNavigate: (chapterId, wordIndex) {
          final bloc = context.read<ReaderBloc>();
          bloc.add(ReaderChapterSelected(chapterId));
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) bloc.add(ReaderWordIndexChanged(wordIndex));
          });
        },
      ),
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    final bloc = context.read<ReaderBloc>();
    final state = bloc.state;
    final result = await showSearch<SearchResult?>(
      context: context,
      delegate: BookSearchDelegate(
        chapters: state.chapters,
        readerRepository: sl<ReaderRepository>(),
        bookId: state.bookId,
        currentChapter: state.currentChapter,
      ),
    );
    if (result != null && mounted) {
      // Navigate to the found chapter and word.
      bloc.add(ReaderChapterSelected(result.chapterId));
      // Delay to let chapter load, then jump to word.
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        bloc.add(ReaderWordIndexChanged(result.wordIndex));
      }
    }
  }

  int _findParagraphIndex(int wordIndex, List<int> wordOffsets) {
    if (wordOffsets.isEmpty) return -1;
    int lo = 0, hi = wordOffsets.length - 1, result = 0;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (wordOffsets[mid] <= wordIndex) {
        result = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return result;
  }

  void _scrollToParagraph(int currentWordIndex) {
    if (!_followVoice.value) return;
    final ctrl = _scrollController;
    if (ctrl == null || !ctrl.hasClients) return;
    if (_wordOffsets.isEmpty || _paragraphKeys.isEmpty) return;

    final paraIndex = _findParagraphIndex(currentWordIndex, _wordOffsets);
    if (paraIndex < 0 || paraIndex >= _paragraphKeys.length) return;
    // Solo scrollear cuando cambia el párrafo activo, no en cada palabra.
    // Evita animaciones superpuestas que causan jitter/stutter.
    if (paraIndex == _lastScrolledParagraphIndex) return;

    _lastScrolledParagraphIndex = paraIndex;

    final keyContext = _paragraphKeys[paraIndex].currentContext;
    if (keyContext != null) {
      Scrollable.ensureVisible(
        keyContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.3,
      );
      return;
    }

    // El párrafo objetivo no está construido: el ListView.builder lo descartó
    // porque el usuario scrolleó lejos. ensureVisible necesita un widget
    // montado, así que saltamos a una posición aproximada (proporcional al
    // índice) para que el ListView lo construya, y lo centramos con precisión
    // en el frame siguiente.
    final frac = paraIndex / _paragraphKeys.length;
    final max = ctrl.position.maxScrollExtent;
    ctrl.jumpTo((frac * max).clamp(0.0, max));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted || paraIndex >= _paragraphKeys.length) return;
      final ctx = _paragraphKeys[paraIndex].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: 0.3,
      );
    });
  }

  void _updateWordOffsets(List<int> offsets) {
    _wordOffsets = offsets;
  }

  /// El usuario hizo scroll manual durante la reproducción: desengancha el
  /// seguidor (para no pelear con su gesto) y ofrece volver con un botón.
  void _onUserScroll() {
    if (_disposed || !mounted || !_followVoice.value) return;
    if (!context.read<ReaderBloc>().state.isTtsActive) return;
    _followVoice.value = false;
    setState(() => _showReturnButton = true);
  }

  /// Vuelve a enganchar el seguidor y re-centra en la palabra que se lee.
  void _returnToReading() {
    _followVoice.value = true;
    _lastScrolledParagraphIndex = -1;
    final idx = context.read<ReaderBloc>().state.currentWordIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && mounted) _scrollToParagraph(idx);
    });
    if (!_disposed && mounted) setState(() => _showReturnButton = false);
  }

  void _listenEstimating() {
    _estimatingSub?.cancel();
    _estimatingSub = sl<DeviceTtsRepository>().estimatingStream.listen((v) {
      if (!_disposed && mounted) setState(() => _isEstimatingProgress = v);
    });
  }

  void _listenTtsStatus() {
    _ttsStatusSub?.cancel();
    final bloc = context.read<ReaderBloc>();
    _ttsStatusSub = sl<DeviceTtsRepository>().statusStream.listen((status) {
      if (status == TtsPlaybackStatus.playing) {
        if (!_sessionStopwatch.isRunning) {
          _sessionStopwatch.start();
          _sessionStartWordIndex = bloc.state.currentWordIndex;
        }
      } else if (status == TtsPlaybackStatus.idle ||
          status == TtsPlaybackStatus.completed ||
          status == TtsPlaybackStatus.error) {
        if (_sessionStopwatch.isRunning) {
          _sessionStopwatch.stop();
          final elapsed = _sessionStopwatch.elapsed;
          final currentWord = bloc.state.currentWordIndex;
          final wordsRead = (currentWord - _sessionStartWordIndex).abs();
          if (elapsed.inSeconds > 5 && wordsRead > 0) {
            sl<ReadingStatsRepository>().recordSession(
              bookId: bloc.state.bookId,
              duration: elapsed,
              wordsRead: wordsRead,
            );
          }
          _sessionStopwatch.reset();
        }
        // La lectura paró: no hay voz que seguir. Re-enganchamos y
        // ocultamos el botón para la próxima sesión.
        _followVoice.value = true;
        if (_showReturnButton && !_disposed && mounted) {
          setState(() => _showReturnButton = false);
        }
      }
    });
  }

  void _openStats() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ReadingStatsSheet(),
    );
  }

  void _openAmbient() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AmbientSoundSheet(),
    );
  }

  /// "Sync now" does TWO things, both critical to the user's mental
  /// model of "make everything aligned":
  ///   1. Save the current position to the backend (multi-device sync).
  ///   2. If TTS is currently speaking, dispatch a `ReaderTtsRestart`
  ///      so the engine and the text-follower tracker re-align at the
  ///      current word. This is essential because the tracker is a
  ///      timer-based estimate on desktop/web that drifts away from
  ///      the actual voice over time — and just saving progress
  ///      doesn't fix that drift. The user complained "sync button
  ///      doesn't fix the desync" precisely because we were missing
  ///      this step.
  void _syncNow() {
    final bloc = context.read<ReaderBloc>();
    final messenger = ScaffoldMessenger.of(context);
    if (bloc.state.currentChapter == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Sin capítulo activo para sincronizar'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    Haptics.light();
    bloc.add(const ReaderProgressSaved());
    final wasActive = bloc.state.isTtsActive;
    if (wasActive) {
      // Force a clean stop→speak cycle at the current word so the
      // engine and the tracker start from the same position.
      bloc.add(const ReaderTtsRestart());
    }
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.cloud_done_rounded, size: 20, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              wasActive
                  ? 'Realineando voz y guardando…'
                  : 'Sincronizando posición…',
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Suscribimos a los streams del DeviceTtsRepository (singleton) UNA
    // sola vez, con las dependencias ya disponibles. Antes esto vivía en
    // build(), lo que ataba la suscripción a la fase de construcción: con
    // reconstrucciones frecuentes (p. ej. el botón de auto-scroll) el
    // callback podía llegar a un State en transición y disparaba
    // setState sobre un Element defunct.
    if (!_streamsSubscribed) {
      _streamsSubscribed = true;
      _listenEstimating();
      _listenTtsStatus();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // FIX (session 11 regression): we ONLY auto-pause on `paused` —
    // never `inactive` and never `hidden`.
    //
    // `inactive` fires too aggressively:
    //   - iOS: TouchID/FaceID prompt, Control Center, app switcher peek
    //   - Android: split-screen focus loss, picture-in-picture, system
    //     dialogs (including OUR own modal sheets in some Android
    //     versions), volume slider overlay
    //   - Web: tab/window momentary focus loss (clicking dev tools,
    //     URL bar, even some animated transitions)
    //
    // The previous handler treated `inactive` the same as `paused` and
    // dispatched `ReaderTtsToggled`, which IMMEDIATELY stopped TTS the
    // moment the user pressed play (because pressing the button briefly
    // shifted focus → `inactive` fired → handler stopped TTS before any
    // audio was generated). Symptom: "TTS makes no sound on web /
    // Android" reported by the user.
    //
    // `paused` is the only state that reliably means "app is fully in
    // the background", which is when we genuinely want to stop the
    // voice and save progress.
    // Split the two side-effects by their tolerance for false positives:
    //   - Saving progress is idempotent and harmless, so it can fire on
    //     the broader `paused | hidden` set (covers backgrounding on
    //     mobile, tab-hide on web).
    //   - Auto-pausing TTS is destructive (kills the playing voice), so
    //     we only do it on the strict `paused` state.
    final shouldSave =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    final shouldStopTts = state == AppLifecycleState.paused;

    if (!shouldSave) return;
    if (!mounted) return;

    try {
      final bloc = context.read<ReaderBloc>();
      bloc.add(const ReaderProgressSaved());
      if (shouldStopTts && bloc.state.isTtsActive) {
        bloc.add(const ReaderTtsToggled());
      }
    } catch (_) {
      // Bloc may already be gone if navigation is in flight.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    // Save any ongoing reading session before dispose.
    if (_sessionStopwatch.isRunning) {
      _sessionStopwatch.stop();
      final wordsRead =
          (context.read<ReaderBloc>().state.currentWordIndex -
                  _sessionStartWordIndex)
              .abs();
      if (_sessionStopwatch.elapsed.inSeconds > 5 && wordsRead > 0) {
        sl<ReadingStatsRepository>().recordSession(
          bookId: context.read<ReaderBloc>().state.bookId,
          duration: _sessionStopwatch.elapsed,
          wordsRead: wordsRead,
        );
      }
    }
    _ttsStatusSub?.cancel();
    _estimatingSub?.cancel();
    _preferencesCubit.close();
    _scrollController?.dispose();
    _followVoice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _preferencesCubit,
      child: BlocBuilder<PreferencesCubit, ReadingPreferences>(
        builder: (context, prefs) {
          final colors = ReadingPaletteColors.resolve(
            prefs.palette,
            Theme.of(context).colorScheme,
          );
          return _buildScaffold(context, prefs, colors);
        },
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    ReadingPreferences prefs,
    ReadingPaletteColors colors,
  ) {
    final bp = breakpointOf(context);

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.space): const _PlayPauseIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft): const _PrevChapterIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowRight):
            const _NextChapterIntent(),
        LogicalKeySet(LogicalKeyboardKey.keyT): const _ToggleTocIntent(),
        // Desktop-friendly shortcuts. Ctrl on Win/Linux, Cmd on macOS;
        // Flutter's LogicalKeyboardKey.control matches either modifier
        // when used as `meta` is not required — but for cross-platform
        // we bind both `control` AND `meta` variants below.
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyB):
            const _OpenBookmarksIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyB):
            const _OpenBookmarksIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS):
            const _SyncNowIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyS):
            const _SyncNowIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
            const _OpenSearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyF):
            const _OpenSearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.comma):
            const _OpenCustomizationIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.comma):
            const _OpenCustomizationIntent(),
      },
      child: Actions(
        actions: <Type, Action>{
          _PlayPauseIntent: _CallbackAction(() {
            final state = context.read<ReaderBloc>().state;
            final hasText = state.currentChapter?.words.isNotEmpty ?? false;
            if (hasText) {
              context.read<ReaderBloc>().add(const ReaderTtsToggled());
            }
          }),
          _PrevChapterIntent: _CallbackAction(
            () => _navigateChapter(context, -1),
          ),
          _NextChapterIntent: _CallbackAction(
            () => _navigateChapter(context, 1),
          ),
          _ToggleTocIntent: _CallbackAction(_toggleToc),
          _OpenBookmarksIntent: _CallbackAction(() => _openBookmarks(context)),
          _SyncNowIntent: _CallbackAction(_syncNow),
          _OpenSearchIntent: _CallbackAction(() => _openSearch(context)),
          _OpenCustomizationIntent: _CallbackAction(_openCustomizationSheet),
        },
        child: Scaffold(
          backgroundColor: colors.background,
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: _showReturnButton
              ? Padding(
                  // Elevado sobre la barra de capítulos (Anterior/Siguiente)
                  // para no taparla.
                  padding: const EdgeInsets.only(bottom: 68),
                  child: FloatingActionButton.extended(
                    onPressed: _returnToReading,
                    backgroundColor: colors.accent,
                    foregroundColor: colors.background,
                    icon: const Icon(Icons.vertical_align_center),
                    label: const Text('Volver a la lectura'),
                  ),
                )
              : null,
          appBar: _immersive
              ? null
              : AppBar(
                  backgroundColor: colors.background,
                  foregroundColor: colors.foreground,
                  surfaceTintColor: Colors.transparent,
                  title: Text(
                    widget.bookTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.foreground),
                  ),
                  actions: _buildAppBarActions(context, bp, colors),
                ),
          drawer: bp.isCompact
              ? Drawer(
                  child: SafeArea(
                    child: _ChapterList(bookTitle: widget.bookTitle),
                  ),
                )
              : null,
          body: MultiBlocListener(
            listeners: [
              // Auto-scroll on chapter change / paragraph transition.
              BlocListener<ReaderBloc, ReaderState>(
                listenWhen: (prev, curr) {
                  if (prev.currentChapter?.id != curr.currentChapter?.id &&
                      curr.currentChapter != null) {
                    return true;
                  }
                  if (curr.isTtsActive &&
                      prev.currentWordIndex != curr.currentWordIndex) {
                    final prevPara = _findParagraphIndex(
                      prev.currentWordIndex,
                      _wordOffsets,
                    );
                    final currPara = _findParagraphIndex(
                      curr.currentWordIndex,
                      _wordOffsets,
                    );
                    if (currPara != prevPara) return true;
                  }
                  return false;
                },
                listener: (context, state) {
                  final chapter = state.currentChapter;
                  if (chapter == null) return;

                  if (chapter.id != _lastChapterId) {
                    _lastChapterId = chapter.id;
                    _lastScrolledParagraphIndex = -1;
                    final oldCtrl = _scrollController;
                    setState(() {
                      _scrollController = ScrollController();
                    });
                    oldCtrl?.dispose();
                    return;
                  }

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _scrollToParagraph(state.currentWordIndex);
                  });
                },
              ),
              // Remote-progress arrival → "Continuando desde otro
              // dispositivo" snackbar with an action to jump. The
              // bloc only puts a `pendingRemoteProgress` into state if
              // the event passed all filters (right book, not our own
              // echo, not older than our last local save), so showing
              // a banner whenever this field flips from null→set is
              // the right trigger.
              BlocListener<ReaderBloc, ReaderState>(
                listenWhen: (prev, curr) =>
                    prev.pendingRemoteProgress != curr.pendingRemoteProgress &&
                    curr.pendingRemoteProgress != null,
                listener: (context, state) {
                  final pending = state.pendingRemoteProgress!;
                  final bloc = context.read<ReaderBloc>();
                  final messenger = ScaffoldMessenger.of(context);
                  // Clear any older sync-snackbar so two devices
                  // updating fast don't stack banners.
                  messenger.clearSnackBars();
                  // Auto-resolves to "dismissed" if the user does
                  // nothing for 8 seconds — keeps a stale banner from
                  // sitting forever.
                  final controller = messenger.showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 8),
                      behavior: SnackBarBehavior.floating,
                      content: Row(
                        children: [
                          const Icon(
                            Icons.devices_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Continuando desde otro dispositivo '
                              '(palabra ${pending.wordIndex})',
                            ),
                          ),
                        ],
                      ),
                      action: SnackBarAction(
                        label: 'Ir allí',
                        onPressed: () =>
                            bloc.add(const ReaderRemoteProgressAccepted()),
                      ),
                    ),
                  );
                  controller.closed.then((reason) {
                    if (!bloc.isClosed &&
                        reason != SnackBarClosedReason.action &&
                        bloc.state.pendingRemoteProgress == pending) {
                      bloc.add(const ReaderRemoteProgressDismissed());
                    }
                  });
                },
              ),
            ],
            child: BlocConsumer<ReaderBloc, ReaderState>(
              listenWhen: (prev, curr) =>
                  curr.errorMessage != null &&
                  prev.errorMessage != curr.errorMessage,
              listener: (context, state) {
                final message = state.errorMessage;
                if (message == null) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(message)));
              },
              buildWhen: (prev, curr) =>
                  prev.status != curr.status ||
                  prev.currentChapter?.id != curr.currentChapter?.id ||
                  prev.currentChapterIndex != curr.currentChapterIndex ||
                  prev.chapters.length != curr.chapters.length,
              builder: (context, state) {
                if (state.status == ReaderStatus.loading &&
                    state.currentChapter == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state.chapters.isEmpty) {
                  return Center(
                    child: Text(
                      'Este libro no tiene capítulos disponibles.',
                      style: TextStyle(color: colors.foreground),
                    ),
                  );
                }

                final chapter = state.currentChapter;
                if (chapter == null) {
                  return Center(
                    child: Text(
                      'No se pudo cargar el capítulo actual.',
                      style: TextStyle(color: colors.foreground),
                    ),
                  );
                }

                return bp.when(
                  compact: () =>
                      _buildCompactBody(context, state, prefs, colors),
                  medium: () => _buildMediumBody(context, state, prefs, colors),
                  expanded: () =>
                      _buildExpandedBody(context, state, prefs, colors),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Build the AppBar actions. Primary actions stay visible; secondary
  /// actions collapse into an overflow menu on compact screens to
  /// reduce clutter.
  List<Widget> _buildAppBarActions(
    BuildContext context,
    LayoutBreakpoint bp,
    ReadingPaletteColors colors,
  ) {
    final compact = bp.isCompact;

    final bookmarkBtn = _BookmarkCountBadge(
      accent: colors.accent,
      onTap: () => _openBookmarks(context),
    );

    final speedBtn = BlocBuilder<ReaderBloc, ReaderState>(
      buildWhen: (prev, curr) => prev.isTtsActive != curr.isTtsActive,
      builder: (context, s) {
        if (!s.isTtsActive) return const SizedBox.shrink();
        return IconButton(
          onPressed: _toggleSpeedBar,
          tooltip: _speedBarVisible
              ? 'Ocultar velocidad'
              : 'Velocidad de lectura',
          icon: Icon(
            _speedBarVisible ? Icons.speed_rounded : Icons.speed_outlined,
            color: _speedBarVisible ? colors.accent : null,
          ),
        );
      },
    );

    final ttsBtn = BlocBuilder<ReaderBloc, ReaderState>(
      buildWhen: (prev, curr) =>
          prev.ttsStatus != curr.ttsStatus ||
          prev.currentChapter?.id != curr.currentChapter?.id,
      builder: (context, state) {
        final hasText = state.currentChapter?.words.isNotEmpty ?? false;
        return IconButton(
          onPressed: hasText
              ? () {
                  Haptics.medium();
                  context.read<ReaderBloc>().add(const ReaderTtsToggled());
                }
              : null,
          icon: Icon(
            state.isTtsActive
                ? Icons.stop_circle_rounded
                : Icons.play_circle_rounded,
            size: 28,
            color: colors.accent,
          ),
          tooltip: state.isTtsActive ? 'Detener audio' : 'Escuchar',
        );
      },
    );

    // Layout strategy:
    //   Compact (phones): TOC + bookmark + speed + voice + overflow + TTS
    //   Medium/Expanded: full row visible
    final tocBtn = bp.isExpanded
        ? IconButton(
            onPressed: _toggleToc,
            icon: Icon(
              _tocVisible ? Icons.menu_book_rounded : Icons.menu_book_outlined,
            ),
            tooltip: 'Índice',
          )
        : (bp.isMedium
              ? IconButton(
                  onPressed: _toggleToc,
                  icon: const Icon(Icons.list_rounded),
                  tooltip: 'Índice',
                )
              : const SizedBox.shrink());

    // Cross-platform shortcut hint suffix for desktop / web. Empty
    // string on mobile to avoid clutter — touch users don't have
    // keyboard shortcuts. Include kIsWeb because desktop browsers
    // accept the same shortcuts via the Shortcuts widget above.
    final platform = defaultTargetPlatform;
    final isKeyboardLikely =
        kIsWeb ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux;
    String hint(String shortcut) => isKeyboardLikely ? '  ($shortcut)' : '';

    final searchBtn = IconButton(
      onPressed: () => _openSearch(context),
      icon: const Icon(Icons.search_rounded),
      tooltip: 'Buscar en el libro${hint('Ctrl+F')}',
    );

    final voiceBtn = IconButton(
      onPressed: _openVoiceMenu,
      icon: const Icon(Icons.record_voice_over_rounded),
      tooltip: 'Voz',
    );

    final statsBtn = IconButton(
      onPressed: _openStats,
      icon: const Icon(Icons.bar_chart_rounded),
      tooltip: 'Estadísticas',
    );

    final customizeBtn = IconButton(
      onPressed: _openCustomizationSheet,
      icon: const Icon(Icons.tune_rounded),
      tooltip: 'Personalizar${hint('Ctrl+,')}',
    );

    final ambientBtn = IconButton(
      onPressed: _openAmbient,
      icon: const Icon(Icons.graphic_eq_rounded),
      tooltip: 'Sonido ambiental',
    );

    final syncBtn = IconButton(
      onPressed: _syncNow,
      icon: const Icon(Icons.sync_rounded),
      tooltip: 'Sincronizar ahora${hint('Ctrl+S')}',
    );

    if (compact) {
      // Compact: only essentials visible, rest in overflow menu.
      return [
        bookmarkBtn,
        speedBtn,
        PopupMenuButton<String>(
          tooltip: 'Más opciones',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (action) {
            switch (action) {
              case 'search':
                _openSearch(context);
                break;
              case 'voice':
                _openVoiceMenu();
                break;
              case 'ambient':
                _openAmbient();
                break;
              case 'sync':
                _syncNow();
                break;
              case 'stats':
                _openStats();
                break;
              case 'customize':
                _openCustomizationSheet();
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'search',
              child: ListTile(
                leading: Icon(Icons.search_rounded),
                title: Text('Buscar'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'voice',
              child: ListTile(
                leading: Icon(Icons.record_voice_over_rounded),
                title: Text('Voz'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'ambient',
              child: ListTile(
                leading: Icon(Icons.graphic_eq_rounded),
                title: Text('Sonido ambiental'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'sync',
              child: ListTile(
                leading: Icon(Icons.sync_rounded),
                title: Text('Sincronizar'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'stats',
              child: ListTile(
                leading: Icon(Icons.bar_chart_rounded),
                title: Text('Estadísticas'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'customize',
              child: ListTile(
                leading: Icon(Icons.tune_rounded),
                title: Text('Personalizar'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        ttsBtn,
        const SizedBox(width: 4),
      ];
    }

    // Medium / Expanded: show full row.
    return [
      tocBtn,
      searchBtn,
      bookmarkBtn,
      speedBtn,
      voiceBtn,
      ambientBtn,
      syncBtn,
      statsBtn,
      customizeBtn,
      ttsBtn,
      const SizedBox(width: 4),
    ];
  }

  void _navigateChapter(BuildContext context, int direction) {
    final state = context.read<ReaderBloc>().state;
    final newIndex = state.currentChapterIndex + direction;
    if (newIndex < 0 || newIndex >= state.chapters.length) return;
    Haptics.light();
    final target = state.chapters[newIndex];
    context.read<ReaderBloc>().add(ReaderChapterSelected(target.id));
  }

  Widget _buildCompactBody(
    BuildContext context,
    ReaderState state,
    ReadingPreferences prefs,
    ReadingPaletteColors colors,
  ) {
    return _ReaderBody(
      state: state,
      prefs: prefs,
      colors: colors,
      immersive: _immersive,
      scrollController: _scrollController,
      followVoice: _followVoice,
      onUserScroll: _onUserScroll,
      paragraphKeys: _paragraphKeys,
      onToggleImmersive: _toggleImmersive,
      onParagraphKeys: (keys) => _paragraphKeys = keys,
      onWordOffsets: _updateWordOffsets,
      onNavigateChapter: (dir) => _navigateChapter(context, dir),
      speedBarVisible: _speedBarVisible,
      onToggleSpeedBar: _toggleSpeedBar,
      isEstimatingProgress: _isEstimatingProgress,
    );
  }

  Widget _buildMediumBody(
    BuildContext context,
    ReaderState state,
    ReadingPreferences prefs,
    ReadingPaletteColors colors,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _tocVisible
              ? SizedBox(
                  width: 280,
                  child: _ChapterList(bookTitle: widget.bookTitle),
                )
              : const SizedBox.shrink(),
        ),
        if (_tocVisible)
          VerticalDivider(width: 1, color: scheme.outlineVariant),
        Expanded(
          child: _ReaderBody(
            state: state,
            prefs: prefs,
            colors: colors,
            immersive: _immersive,
            scrollController: _scrollController,
            followVoice: _followVoice,
            onUserScroll: _onUserScroll,
            paragraphKeys: _paragraphKeys,
            onToggleImmersive: _toggleImmersive,
            onParagraphKeys: (keys) => _paragraphKeys = keys,
            onWordOffsets: _updateWordOffsets,
            onNavigateChapter: (dir) => _navigateChapter(context, dir),
            speedBarVisible: _speedBarVisible,
            onToggleSpeedBar: _toggleSpeedBar,
            isEstimatingProgress: _isEstimatingProgress,
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedBody(
    BuildContext context,
    ReaderState state,
    ReadingPreferences prefs,
    ReadingPaletteColors colors,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _tocVisible
              ? SizedBox(
                  width: 320,
                  child: _ChapterList(bookTitle: widget.bookTitle),
                )
              : const SizedBox.shrink(),
        ),
        if (_tocVisible)
          VerticalDivider(width: 1, color: scheme.outlineVariant),
        Expanded(
          flex: 3,
          child: _ReaderBody(
            state: state,
            prefs: prefs,
            colors: colors,
            immersive: _immersive,
            scrollController: _scrollController,
            followVoice: _followVoice,
            onUserScroll: _onUserScroll,
            paragraphKeys: _paragraphKeys,
            onToggleImmersive: _toggleImmersive,
            onParagraphKeys: (keys) => _paragraphKeys = keys,
            onWordOffsets: _updateWordOffsets,
            onNavigateChapter: (dir) => _navigateChapter(context, dir),
            speedBarVisible: _speedBarVisible,
            onToggleSpeedBar: _toggleSpeedBar,
            isEstimatingProgress: _isEstimatingProgress,
          ),
        ),
      ],
    );
  }
}

// ── Chapter list sidebar widget ──

class _ChapterList extends StatelessWidget {
  const _ChapterList({required this.bookTitle});

  final String bookTitle;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReaderBloc, ReaderState>(
      buildWhen: (prev, curr) =>
          prev.chapters != curr.chapters ||
          prev.currentChapterIndex != curr.currentChapterIndex,
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bookTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${state.chapters.length} capítulos',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: state.chapters.length,
                itemBuilder: (context, index) {
                  final chapter = state.chapters[index];
                  final isSelected = state.currentChapterIndex == index;
                  return ListTile(
                    selected: isSelected,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    title: Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () {
                      if (breakpointOf(context).isCompact) {
                        Navigator.of(context).pop();
                      }
                      context.read<ReaderBloc>().add(
                        ReaderChapterSelected(chapter.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Reader body (shared across breakpoints) ──

class _ReaderBody extends StatefulWidget {
  const _ReaderBody({
    required this.state,
    required this.prefs,
    required this.colors,
    required this.immersive,
    required this.scrollController,
    required this.followVoice,
    required this.onUserScroll,
    required this.paragraphKeys,
    required this.onToggleImmersive,
    required this.onParagraphKeys,
    required this.onWordOffsets,
    required this.onNavigateChapter,
    required this.speedBarVisible,
    required this.onToggleSpeedBar,
    this.isEstimatingProgress = false,
  });

  final ReaderState state;
  final ReadingPreferences prefs;
  final ReadingPaletteColors colors;
  final bool immersive;
  final ScrollController? scrollController;
  final ValueListenable<bool> followVoice;
  final VoidCallback onUserScroll;
  final List<GlobalKey> paragraphKeys;
  final VoidCallback onToggleImmersive;
  final void Function(List<GlobalKey>) onParagraphKeys;
  final void Function(List<int>) onWordOffsets;
  final void Function(int) onNavigateChapter;
  final bool speedBarVisible;
  final VoidCallback onToggleSpeedBar;
  final bool isEstimatingProgress;

  @override
  State<_ReaderBody> createState() => _ReaderBodyState();
}

class _ReaderBodyState extends State<_ReaderBody> {
  String? _cachedChapterId;
  List<String> _cachedParagraphs = const [];
  List<int> _cachedWordOffsets = const [];
  List<GlobalKey> _cachedKeys = const [];
  int _cachedChapterWordMax = 0;

  void _recomputeIfNeeded() {
    final chapter = widget.state.currentChapter;
    if (chapter == null) return;
    if (chapter.id == _cachedChapterId) return;

    final paragraphs = chapter.paragraphs.isEmpty
        ? <String>[chapter.text ?? '']
        : chapter.paragraphs;
    final offsets = <int>[];
    int cursor = 0;
    for (final para in paragraphs) {
      offsets.add(cursor);
      cursor += para.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    }
    _cachedChapterId = chapter.id;
    _cachedParagraphs = paragraphs;
    _cachedWordOffsets = offsets;
    _cachedKeys = List.generate(paragraphs.length, (_) => GlobalKey());
    _cachedChapterWordMax = chapter.words.isNotEmpty
        ? chapter.words.length
        : chapter.wordCount;

    widget.onWordOffsets(_cachedWordOffsets);
    widget.onParagraphKeys(_cachedKeys);
  }

  @override
  void initState() {
    super.initState();
    _recomputeIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _ReaderBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _recomputeIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final prefs = widget.prefs;
    final colors = widget.colors;
    final scheme = Theme.of(context).colorScheme;

    final chapter = state.currentChapter;
    if (chapter == null) {
      return Center(
        child: Text(
          'No se pudo cargar el capítulo actual.',
          style: TextStyle(color: colors.foreground),
        ),
      );
    }

    final paragraphs = _cachedParagraphs;
    final wordOffsets = _cachedWordOffsets;
    final paragraphKeys = _cachedKeys;
    final chapterWordMax = _cachedChapterWordMax;

    return NotificationListener<UserScrollNotification>(
      onNotification: (n) {
        if (n.direction != ScrollDirection.idle) {
          widget.onUserScroll();
        }
        return false;
      },
      child: GestureDetector(
        onTap: widget.onToggleImmersive,
        // Horizontal swipe → previous / next chapter (mobile gesture).
        // Threshold of 600 px/s avoids accidental triggers from slow scrolls
        // or from the slider/text-selection drag handles.
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() < 600) return;
          if (velocity > 0) {
            // Swipe right → previous chapter.
            widget.onNavigateChapter(-1);
          } else {
            // Swipe left → next chapter.
            widget.onNavigateChapter(1);
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            if (!widget.immersive)
              BlocBuilder<ReaderBloc, ReaderState>(
                buildWhen: (prev, curr) =>
                    prev.progress != curr.progress ||
                    prev.currentChapterIndex != curr.currentChapterIndex ||
                    prev.chapters.length != curr.chapters.length,
                builder: (context, s) {
                  final cn = s.currentChapterIndex + 1;
                  final tc = s.totalChapters;
                  final pct = (s.progress * 100)
                      .clamp(0, 100)
                      .toStringAsFixed(1);
                  return _ChapterHeader(
                    chapterNumber: cn,
                    totalChapters: tc,
                    percent: pct,
                    progress: s.progress,
                    foreground: colors.foreground,
                    accent: colors.accent,
                  );
                },
              ),
            if (!widget.immersive && chapterWordMax > 0)
              BlocBuilder<ReaderBloc, ReaderState>(
                buildWhen: (prev, curr) =>
                    prev.ttsStatus != curr.ttsStatus ||
                    prev.currentWordIndex != curr.currentWordIndex,
                builder: (context, s) => _PositionSlider(
                  currentWord: s.currentWordIndex,
                  maxWords: chapterWordMax,
                  ttsStatus: s.ttsStatus,
                  isEstimatingProgress: widget.isEstimatingProgress,
                  foreground: colors.foreground,
                  accent: colors.accent,
                  // Commit only when the user releases the thumb. Routing
                  // ReaderWordIndexChanged through onChangeEnd instead of
                  // onChanged is what stops the Material Slider's per-rebuild
                  // ghost ticks (~once per tracker emission on Web/Desktop)
                  // from cascading into a stop()/restart of TTS.
                  onChangeEnd: (v) => context.read<ReaderBloc>().add(
                    ReaderWordIndexChanged(v.round()),
                  ),
                ),
              ),
            // ── Speed control bar (only when user toggles it on) ──
            if (!widget.immersive)
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: widget.speedBarVisible
                    ? _InlineSpeedBar(
                        accent: colors.accent,
                        foreground: colors.foreground,
                        onClose: widget.onToggleSpeedBar,
                      )
                    : const SizedBox.shrink(),
              ),
            Expanded(
              child: Builder(
                builder: (context) {
                  final textStyle = TextStyle(
                    color: colors.foreground,
                    fontSize: prefs.fontSize,
                    height: prefs.lineHeight,
                    letterSpacing: prefs.letterSpacing,
                    fontFamily: prefs.fontFamilyName,
                  );

                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: prefs.maxColumnWidth,
                      ),
                      child: ListView.builder(
                        key: ValueKey(prefs.fontFamilyName),
                        controller: widget.scrollController,
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        itemCount: paragraphs.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            final chapter = widget.state.currentChapter;
                            return _EditorialChapterHeader(
                              chapterNumber:
                                  widget.state.currentChapterIndex + 1,
                              chapterTitle: chapter?.title ?? '',
                              foreground: colors.foreground,
                            );
                          }
                          final paraIndex = index - 1;
                          final endIdx = (paraIndex + 1 < wordOffsets.length)
                              ? wordOffsets[paraIndex + 1] - 1
                              : chapterWordMax - 1;
                          return _ParagraphHighlightProxy(
                            key: paraIndex < paragraphKeys.length
                                ? paragraphKeys[paraIndex]
                                : null,
                            followVoice: widget.followVoice,
                            paragraph: paragraphs[paraIndex],
                            startWordIndex: wordOffsets[paraIndex],
                            endWordIndex: endIdx,
                            textStyle: textStyle,
                            accentColor: colors.accent,
                            isFirstParagraph: paraIndex == 0,
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            if (!widget.immersive)
              _ChapterNavBar(
                canPrev: state.currentChapterIndex > 0,
                canNext: state.currentChapterIndex < state.chapters.length - 1,
                foreground: colors.foreground,
                background: scheme.surfaceContainerHighest,
                onPrev: () => widget.onNavigateChapter(-1),
                onNext: () => widget.onNavigateChapter(1),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ──

class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({
    required this.chapterNumber,
    required this.totalChapters,
    required this.percent,
    required this.progress,
    required this.foreground,
    required this.accent,
  });

  final int chapterNumber;
  final int totalChapters;
  final String percent;
  final double progress;
  final Color foreground;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Capítulo $chapterNumber de $totalChapters',
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            label: 'Progreso del capítulo: $percent porciento',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: foreground.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorialChapterHeader extends StatelessWidget {
  const _EditorialChapterHeader({
    required this.chapterNumber,
    required this.chapterTitle,
    required this.foreground,
  });

  final int chapterNumber;
  final String chapterTitle;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        children: [
          Text(
            '$chapterNumber',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: foreground,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 60,
            child: Divider(
              height: 1,
              thickness: 1,
              color: foreground.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            chapterTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: foreground.withValues(alpha: 0.9),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionSlider extends StatefulWidget {
  const _PositionSlider({
    required this.currentWord,
    required this.maxWords,
    required this.ttsStatus,
    required this.foreground,
    required this.accent,
    required this.onChangeEnd,
    this.isEstimatingProgress = false,
  });

  final int currentWord;
  final int maxWords;
  final TtsPlaybackStatus ttsStatus;
  final Color foreground;
  final Color accent;
  final ValueChanged<double> onChangeEnd;
  final bool isEstimatingProgress;

  @override
  State<_PositionSlider> createState() => _PositionSliderState();
}

class _PositionSliderState extends State<_PositionSlider> {
  // Local drag state. While the user is actively dragging the thumb we
  // ignore external updates of `currentWord` (which the TTS tracker emits
  // multiple times per second). The slider value stays under the user's
  // finger, and we only push the final position back to the bloc on
  // onChangeEnd. This is the same pattern used by _InlineSpeedBar and is
  // what eliminates the "ghost tick" cascade observed on Web/Desktop —
  // where rebuilding the Slider on every tracker emission used to fire
  // spurious onChanged events that stopped TTS playback.
  bool _isDragging = false;
  double _dragValue = 0;

  double get _effectiveValue {
    final maxD = widget.maxWords.toDouble();
    if (_isDragging) return _dragValue.clamp(0, maxD);
    return widget.currentWord.toDouble().clamp(0, maxD);
  }

  void _onChangeStart(double value) {
    setState(() {
      _isDragging = true;
      _dragValue = value;
    });
  }

  void _onChanged(double value) {
    if (!_isDragging) return;
    setState(() => _dragValue = value);
  }

  void _onChangeEnd(double value) {
    setState(() {
      _isDragging = false;
      _dragValue = value;
    });
    widget.onChangeEnd(value);
  }

  @override
  Widget build(BuildContext context) {
    final indicator = switch (widget.ttsStatus) {
      TtsPlaybackStatus.loading => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      TtsPlaybackStatus.playing => Icon(
        Icons.graphic_eq_rounded,
        size: 16,
        color: widget.accent,
      ),
      TtsPlaybackStatus.error => const Icon(
        Icons.volume_off_rounded,
        size: 16,
        color: Colors.red,
      ),
      _ => const SizedBox.shrink(),
    };

    final estimateBadge =
        widget.isEstimatingProgress &&
            (widget.ttsStatus == TtsPlaybackStatus.playing ||
                widget.ttsStatus == TtsPlaybackStatus.loading)
        ? Tooltip(
            message: 'Sincronización aproximada',
            child: Icon(
              Icons.bolt_rounded,
              size: 14,
              color: widget.foreground.withValues(alpha: 0.5),
            ),
          )
        : const SizedBox.shrink();

    final displayedWord = _effectiveValue.round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$displayedWord / ${widget.maxWords} palabras',
                style: TextStyle(
                  color: widget.foreground.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              estimateBadge,
              const SizedBox(width: 4),
              indicator,
              _ReadingTimer(color: widget.foreground.withValues(alpha: 0.7)),
            ],
          ),
          Semantics(
            label:
                'Posición de lectura: $displayedWord de '
                '${widget.maxWords} palabras',
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: widget.accent,
                inactiveTrackColor: widget.foreground.withValues(alpha: 0.15),
                thumbColor: widget.accent,
                overlayColor: widget.accent.withValues(alpha: 0.1),
                trackHeight: 3,
              ),
              child: Slider(
                value: _effectiveValue,
                min: 0,
                max: widget.maxWords.toDouble(),
                onChangeStart: _onChangeStart,
                onChanged: _onChanged,
                onChangeEnd: _onChangeEnd,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingTimer extends StatelessWidget {
  const _ReadingTimer({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReaderBloc, ReaderState>(
      buildWhen: (prev, curr) =>
          prev.ttsElapsed.inSeconds != curr.ttsElapsed.inSeconds,
      builder: (context, state) {
        if (!state.isTtsActive && state.ttsElapsed == Duration.zero) {
          return const SizedBox.shrink();
        }
        final d = state.ttsElapsed;
        final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
        final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
        final hh = d.inHours;
        final text = hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}

class _ParagraphHighlightProxy extends StatefulWidget {
  const _ParagraphHighlightProxy({
    required this.followVoice,
    required this.paragraph,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.textStyle,
    this.accentColor,
    this.isFirstParagraph = false,
    super.key,
  });

  final ValueListenable<bool> followVoice;
  final String paragraph;
  final int startWordIndex;
  final int endWordIndex;
  final TextStyle textStyle;
  final Color? accentColor;
  final bool isFirstParagraph;

  @override
  State<_ParagraphHighlightProxy> createState() =>
      _ParagraphHighlightProxyState();
}

class _ParagraphHighlightProxyState extends State<_ParagraphHighlightProxy> {
  static final _sentenceEnd = RegExp(r'(?<=[.!?…])\s+');
  static final _wsRegex = RegExp(r'\s+');

  late List<_Sentence> _sentences;
  late List<GlobalKey> _sentenceKeys;

  @override
  void initState() {
    super.initState();
    _sentences = _splitSentences();
  }

  @override
  void didUpdateWidget(covariant _ParagraphHighlightProxy old) {
    super.didUpdateWidget(old);
    if (old.paragraph != widget.paragraph ||
        old.startWordIndex != widget.startWordIndex) {
      _sentences = _splitSentences();
    }
  }

  List<_Sentence> _splitSentences() {
    final parts = widget.paragraph.split(_sentenceEnd);
    final sentences = <_Sentence>[];
    int wordCursor = widget.startWordIndex;
    for (final part in parts) {
      final wordCount = part.split(_wsRegex).where((w) => w.isNotEmpty).length;
      if (wordCount == 0) continue;
      sentences.add(
        _Sentence(
          text: part,
          wordStart: wordCursor,
          wordEnd: wordCursor + wordCount - 1,
        ),
      );
      wordCursor += wordCount;
    }
    _sentenceKeys = List.generate(sentences.length, (_) => GlobalKey());
    return sentences;
  }

  int _activeSentenceIndex(int wordIndex) {
    if (wordIndex < widget.startWordIndex || wordIndex > widget.endWordIndex) {
      return -1;
    }
    for (var i = 0; i < _sentences.length; i++) {
      final s = _sentences[i];
      if (wordIndex >= s.wordStart && wordIndex <= s.wordEnd) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    const indentWidth = 24.0;
    final padding = EdgeInsets.only(
      left: 12,
      right: 12,
      top: widget.isFirstParagraph ? 0 : 4,
      bottom: 4,
    );

    if (_sentences.isEmpty) {
      return Padding(
        padding: padding,
        child: Text(
          widget.paragraph,
          textAlign: TextAlign.justify,
          style: widget.textStyle,
        ),
      );
    }

    return RepaintBoundary(
      child: BlocConsumer<ReaderBloc, ReaderState>(
        listenWhen: (prev, curr) {
          if (!curr.isTtsActive) return false;
          final prevIdx = _activeSentenceIndex(prev.currentWordIndex);
          final currIdx = _activeSentenceIndex(curr.currentWordIndex);
          return currIdx >= 0 && currIdx != prevIdx;
        },
        listener: (context, state) {
          if (!widget.followVoice.value) return;
          final idx = _activeSentenceIndex(state.currentWordIndex);
          if (idx < 0 || idx >= _sentenceKeys.length) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final keyCtx = _sentenceKeys[idx].currentContext;
            if (keyCtx == null) return;
            Scrollable.ensureVisible(
              keyCtx,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              alignment: 0.3,
            );
          });
        },
        buildWhen: (prev, curr) {
          final wasActive = prev.isTtsActive;
          final isActive = curr.isTtsActive;
          if (wasActive != isActive) return true;
          if (!isActive && !wasActive) return false;
          final prevIdx = _activeSentenceIndex(prev.currentWordIndex);
          final currIdx = _activeSentenceIndex(curr.currentWordIndex);
          return prevIdx != currIdx;
        },
        builder: (context, state) {
          final activeIdx = state.isTtsActive
              ? _activeSentenceIndex(state.currentWordIndex)
              : -1;
          final highlight =
              (widget.accentColor ??
                      Theme.of(context).colorScheme.primaryContainer)
                  .withValues(alpha: 0.12);

          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _sentences.length; i++)
                  AnimatedContainer(
                    key: _sentenceKeys[i],
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(
                      vertical: 2,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      color: i == activeIdx ? highlight : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: i == 0
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              SizedBox(width: indentWidth),
                              Expanded(
                                child: Text(
                                  _sentences[i].text,
                                  textAlign: TextAlign.justify,
                                  style: widget.textStyle,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            _sentences[i].text,
                            textAlign: TextAlign.justify,
                            style: widget.textStyle,
                          ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Sentence {
  const _Sentence({
    required this.text,
    required this.wordStart,
    required this.wordEnd,
  });
  final String text;
  final int wordStart;
  final int wordEnd;
}

class _ChapterNavBar extends StatelessWidget {
  const _ChapterNavBar({
    required this.canPrev,
    required this.canNext,
    required this.foreground,
    required this.background,
    required this.onPrev,
    required this.onNext,
  });

  final bool canPrev;
  final bool canNext;
  final Color foreground;
  final Color background;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: background,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canPrev ? onPrev : null,
                icon: const Icon(Icons.chevron_left_rounded),
                label: const Text('Anterior'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: canNext ? onNext : null,
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Siguiente'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Keyboard shortcuts ──

class _PlayPauseIntent extends Intent {
  const _PlayPauseIntent();
}

class _PrevChapterIntent extends Intent {
  const _PrevChapterIntent();
}

class _NextChapterIntent extends Intent {
  const _NextChapterIntent();
}

class _OpenBookmarksIntent extends Intent {
  const _OpenBookmarksIntent();
}

class _SyncNowIntent extends Intent {
  const _SyncNowIntent();
}

class _OpenSearchIntent extends Intent {
  const _OpenSearchIntent();
}

class _OpenCustomizationIntent extends Intent {
  const _OpenCustomizationIntent();
}

class _ToggleTocIntent extends Intent {
  const _ToggleTocIntent();
}

class _CallbackAction extends Action<Intent> {
  _CallbackAction(this.callback);
  final VoidCallback callback;

  @override
  Object? invoke(Intent intent) {
    callback();
    return null;
  }
}

// ── Voice menu sheet ──

class _VoiceMenuSheet extends StatefulWidget {
  const _VoiceMenuSheet();

  @override
  State<_VoiceMenuSheet> createState() => _VoiceMenuSheetState();
}

class _VoiceMenuSheetState extends State<_VoiceMenuSheet> {
  List<Map<String, String>> _nativeVoices = const [];
  Map<String, String>? _selectedNative;
  bool _loading = true;
  TtsMode _mode = TtsMode.device;
  TtsCapabilities _caps = kIsWeb
      ? TtsCapabilities.web
      : _isDesktopPlatform
      ? TtsCapabilities.desktop
      : TtsCapabilities.mobile;

  static bool get _isDesktopPlatform =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mode = await getTtsMode();
    final selected = await getNativeVoice();
    final all = _caps.supportsVoiceSelection
        ? await sl<DeviceTtsRepository>().getAvailableVoices()
        : const <Map<String, String>>[];
    final filtered =
        all.where((v) {
          final loc = (v['locale'] ?? '').toLowerCase();
          return loc.startsWith('es') || loc.startsWith('en');
        }).toList()..sort((a, b) {
          final aNeural = _isNeuralVoice(a) ? 0 : 1;
          final bNeural = _isNeuralVoice(b) ? 0 : 1;
          if (aNeural != bNeural) return aNeural.compareTo(bNeural);
          return (a['locale'] ?? '').compareTo(b['locale'] ?? '');
        });
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _selectedNative = selected ?? sl<DeviceTtsRepository>().selectedVoice;
      _nativeVoices = filtered.isEmpty ? all : filtered;
      _loading = false;
      if (sl.isRegistered<TtsCapabilities>()) {
        _caps = sl<TtsCapabilities>();
      }
    });
  }

  Future<void> _selectNative(Map<String, String> voice) async {
    final bloc = context.read<ReaderBloc>();
    final wasActive = bloc.state.isTtsActive;
    Navigator.pop(context);
    await setTtsMode(TtsMode.device);
    await setNativeVoice(voice);
    await sl<DeviceTtsRepository>().setVoice(voice);
    if (sl.isRegistered<TtsRepositoryProxy>()) {
      await sl<TtsRepositoryProxy>().switchMode(TtsMode.device);
    }
    if (wasActive) bloc.add(const ReaderTtsRestart());
  }

  String _voiceSubtitle(Map<String, String> v) {
    final locale = v['locale'] ?? '';
    final gender = v['gender'];
    final neural = _isNeuralVoice(v) ? 'Neural' : '';
    final parts = [
      locale,
      gender,
      neural,
    ].where((p) => p != null && p.isNotEmpty);
    return parts.join(' · ');
  }

  bool _isNativeSelected(Map<String, String> v) {
    final s = _selectedNative;
    if (s == null) return false;
    return s['name'] == v['name'] && s['locale'] == v['locale'];
  }

  bool _isNeuralVoice(Map<String, String> v) {
    final name = (v['name'] ?? '').toLowerCase();
    return name.contains('natural') ||
        name.contains('neural') ||
        name.contains('wavenet') ||
        name.contains('neural2');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Semantics(
        label: 'Menú de selección de voz',
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'Voz para audio',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    kIsWeb
                        ? 'Voces del navegador'
                        : _caps.supportsEngineQuery
                        ? 'Voces del dispositivo'
                        : 'Voces disponibles',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (!_caps.supportsVoiceSelection)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      'La selección de voz no está disponible en esta plataforma.',
                      style: TextStyle(fontSize: 13),
                    ),
                  )
                else if (_nativeVoices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      'No hay voces nativas disponibles en este sistema.',
                      style: TextStyle(fontSize: 13),
                    ),
                  )
                else
                  for (final v in _nativeVoices)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        _isNeuralVoice(v)
                            ? Icons.auto_awesome_rounded
                            : _isDesktopPlatform
                            ? Icons.desktop_windows_rounded
                            : Icons.phone_android_rounded,
                        color: _isNativeSelected(v) && _mode == TtsMode.device
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(v['name'] ?? '—'),
                      subtitle: Text(_voiceSubtitle(v)),
                      trailing: _isNativeSelected(v) && _mode == TtsMode.device
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => _selectNative(v),
                    ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text(
                    'Mejorar voces (gratuito)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    kIsWeb
                        ? 'Instala voces de mayor calidad en tu navegador/SO y aparecerán aquí automáticamente.'
                        : 'Descarga voces de mayor calidad en los ajustes de tu dispositivo y aparecerán aquí automáticamente.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final tip in _voiceTips)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      tip.icon,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      tip.title,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      tip.subtitle,
                      style: const TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                const Divider(height: 1),
                _TtsSpeedSelector(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Inline Speed Bar (visible during TTS playback) ──

class _InlineSpeedBar extends StatefulWidget {
  const _InlineSpeedBar({
    required this.accent,
    required this.foreground,
    required this.onClose,
  });
  final Color accent;
  final Color foreground;
  final VoidCallback onClose;

  @override
  State<_InlineSpeedBar> createState() => _InlineSpeedBarState();
}

class _InlineSpeedBarState extends State<_InlineSpeedBar> {
  double _rate = 0.6;

  @override
  void initState() {
    super.initState();
    _rate = sl<DeviceTtsRepository>().speechRate;
  }

  String _rateLabel(double rate) {
    // Map internal rate (0.0–1.0) to human-readable multiplier.
    // 0.6 = x1, 0.7 = x1.25, 0.8 = x1.5, 0.9 = x1.75, 1.0 = x2
    final multiplier = ((rate - 0.6) / 0.4 * 1.0 + 1.0).clamp(0.5, 2.0);
    return 'x${multiplier.toStringAsFixed(2)}';
  }

  void _onChanged(double value) {
    // FIX (desync): only update the visual label during drag. Calling
    // sl<DeviceTtsRepository>().speechRate = ... here triggered the
    // setter on every tick, which (a) sent setSpeechRate to the engine
    // many times async, and (b) restarted the segment tracker with the
    // NEW rate's timing while the engine was still speaking at the OLD
    // rate. The result: tracker advanced/lagged independently of voice,
    // and on the next pause/resume the BLoC's currentWordIndex was far
    // from where the engine actually was — visible as the highlight
    // landing on the wrong word after resuming.
    final clamped = value.clamp(0.3, 1.0);
    setState(() => _rate = clamped);
  }

  void _onChangeEnd(double value) {
    // Commit the rate change exactly once when the user releases the
    // slider. ReaderTtsRestart does a clean stop()+speak(startIdx) so
    // the engine and tracker re-align at the same word position.
    final clamped = _rate.clamp(0.3, 1.0);
    sl<DeviceTtsRepository>().speechRate = clamped;
    setTtsSpeechRate(clamped);
    final bloc = context.read<ReaderBloc>();
    if (bloc.state.isTtsActive) {
      bloc.add(const ReaderTtsRestart());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      ),
      child: Row(
        children: [
          Icon(
            Icons.slow_motion_video_rounded,
            size: 18,
            color: widget.foreground.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: widget.accent,
                inactiveTrackColor: widget.accent.withValues(alpha: 0.25),
                thumbColor: widget.accent,
              ),
              child: Slider(
                value: _rate,
                min: 0.3,
                max: 1.0,
                onChanged: _onChanged,
                onChangeEnd: _onChangeEnd,
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 42,
            child: Text(
              _rateLabel(_rate),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: widget.foreground.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Ocultar',
            onPressed: widget.onClose,
            icon: Icon(
              Icons.close_rounded,
              color: widget.foreground.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bookmark count badge button ──
//
// Stateful widget that owns its own bookmark count cache and refreshes
// when (a) the active book changes via the ReaderBloc, or (b) any
// bookmark add/remove fires on BookmarkRepository.changes. Previously
// this was inlined as a chain of `StreamBuilder<String> > BlocBuilder >
// FutureBuilder`, but the nested FutureBuilder rebuilt with a fresh
// Future on every parent rebuild — producing brief windows where
// snap.data was null and onPressed wasn't yet bound to the freshly
// rendered IconButton, which the user perceived as "the button does
// nothing on the first tap".
class _BookmarkCountBadge extends StatefulWidget {
  const _BookmarkCountBadge({required this.accent, required this.onTap});

  final Color accent;
  final VoidCallback onTap;

  @override
  State<_BookmarkCountBadge> createState() => _BookmarkCountBadgeState();
}

class _BookmarkCountBadgeState extends State<_BookmarkCountBadge> {
  int _count = 0;
  String? _watchedBookId;
  StreamSubscription<String>? _changesSub;

  @override
  void initState() {
    super.initState();
    _changesSub = sl<BookmarkRepository>().changes.listen((bookId) {
      if (bookId == _watchedBookId) _refresh();
    });
    // Initial fetch deferred to didChangeDependencies so we have a bloc.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bookId = context.read<ReaderBloc>().state.bookId;
    if (bookId.isNotEmpty && bookId != _watchedBookId) {
      _watchedBookId = bookId;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final bookId = _watchedBookId;
    if (bookId == null || bookId.isEmpty) return;
    final list = await sl<BookmarkRepository>().getBookmarks(bookId);
    if (!mounted) return;
    setState(() => _count = list.length);
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to BLoC bookId changes so the badge refreshes when the
    // user navigates between books without unmounting the reader page.
    return BlocListener<ReaderBloc, ReaderState>(
      listenWhen: (prev, curr) => prev.bookId != curr.bookId,
      listener: (_, s) {
        _watchedBookId = s.bookId;
        _refresh();
      },
      child: IconButton(
        onPressed: widget.onTap,
        tooltip: 'Marcadores ($_count)',
        icon: _count > 0
            ? Badge(
                label: Text('$_count'),
                backgroundColor: widget.accent,
                child: const Icon(Icons.bookmarks_rounded),
              )
            : const Icon(Icons.bookmarks_outlined),
      ),
    );
  }
}

// ── TTS Speed Selector ──

class _TtsSpeedSelector extends StatefulWidget {
  @override
  State<_TtsSpeedSelector> createState() => _TtsSpeedSelectorState();
}

class _TtsSpeedPreset {
  const _TtsSpeedPreset(this.label, this.multiplier, this.rate);
  final String label;
  final double multiplier;
  final double rate;
}

const _kSpeedPresets = [
  _TtsSpeedPreset('x1', 1.0, 0.6),
  _TtsSpeedPreset('x1.25', 1.25, 0.7),
  _TtsSpeedPreset('x1.5', 1.5, 0.8),
  _TtsSpeedPreset('x1.75', 1.75, 0.9),
  _TtsSpeedPreset('x2', 2.0, 1.0),
];

class _TtsSpeedSelectorState extends State<_TtsSpeedSelector> {
  double _rate = 0.6;

  @override
  void initState() {
    super.initState();
    _loadRate();
  }

  Future<void> _loadRate() async {
    final rate = await getTtsSpeechRate();
    if (mounted) setState(() => _rate = rate);
  }

  void _onPresetSelected(_TtsSpeedPreset preset) {
    setState(() => _rate = preset.rate);
    sl<DeviceTtsRepository>().speechRate = preset.rate;
    setTtsSpeechRate(preset.rate);
    // Restart playback so the new rate applies immediately to the current
    // utterance instead of waiting for the next segment.
    final bloc = context.read<ReaderBloc>();
    if (bloc.state.isTtsActive) {
      bloc.add(const ReaderTtsRestart());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed_rounded, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Velocidad de lectura',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: _kSpeedPresets.map((preset) {
              final selected = (_rate - preset.rate).abs() < 0.01;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(preset.label),
                  selected: selected,
                  onSelected: (_) => _onPresetSelected(preset),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? scheme.onPrimary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Free voice tips ──

class _VoiceTip {
  const _VoiceTip(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title;
  final String subtitle;
}

List<_VoiceTip> get _voiceTips {
  if (kIsWeb) {
    return const [
      _VoiceTip(
        Icons.web,
        'Chrome/Edge',
        'Instala voces del SO; Chrome las detecta automáticamente',
      ),
      _VoiceTip(
        Icons.travel_explore,
        'Firefox',
        'about:config → media.webspeech.synth.enabled = true',
      ),
      _VoiceTip(
        Icons.auto_awesome,
        'Tip',
        'Las voces "Neural", "Natural" o "Enhanced" suenan mucho mejor que las estándar',
      ),
    ];
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
      return const [
        _VoiceTip(
          Icons.desktop_windows,
          'Windows',
          'Configuración → Hora e idioma → Voz → Añadir voces (Natural Voices)',
        ),
        _VoiceTip(
          Icons.auto_awesome,
          'Tip',
          'Las voces "Neural", "Natural" o "Enhanced" suenan mucho mejor que las estándar',
        ),
      ];
    case TargetPlatform.macOS:
      return const [
        _VoiceTip(
          Icons.desktop_mac,
          'macOS',
          'Ajustes del Sistema → Accesibilidad → Contenido hablado → Voces → Descargar "Enhanced"',
        ),
        _VoiceTip(
          Icons.auto_awesome,
          'Tip',
          'Las voces "Neural", "Natural" o "Enhanced" suenan mucho mejor que las estándar',
        ),
      ];
    case TargetPlatform.linux:
      return const [
        _VoiceTip(
          Icons.computer,
          'Linux',
          'Instala espeak-ng o speech-dispatcher con voces adicionales',
        ),
        _VoiceTip(
          Icons.auto_awesome,
          'Tip',
          'Las voces "Neural", "Natural" o "Enhanced" suenan mucho mejor que las estándar',
        ),
      ];
    case TargetPlatform.iOS:
      return const [
        _VoiceTip(
          Icons.phone_iphone,
          'iOS',
          'Ajustes → Accesibilidad → Contenido hablado → Voces → Descargar "Enhanced"',
        ),
        _VoiceTip(
          Icons.auto_awesome,
          'Tip',
          'Las voces "Neural", "Natural" o "Enhanced" suenan mucho mejor que las estándar',
        ),
      ];
    default:
      return const [
        _VoiceTip(
          Icons.phone_android,
          'Android',
          'Ajustes → Sistema → Idioma → TTS → Instalar voces de Google (Neural2)',
        ),
        _VoiceTip(
          Icons.auto_awesome,
          'Tip',
          'Las voces "Neural", "Natural" o "Enhanced" suenan mucho mejor que las estándar',
        ),
      ];
  }
}
