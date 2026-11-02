import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/focus/focus_prefs.dart';
import '../../../../core/focus/quiet_mode.dart';
import '../../../../core/focus/system_fullscreen.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../../core/storage/local_book_store.dart';
import '../../../../core/sync/client_id_service.dart';
import '../../../../core/sync/sync_stream_client.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../core/utils/sorted_lookup.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../settings/domain/entities/reading_preferences.dart';
import '../../../settings/presentation/cubit/preferences_cubit.dart';
import '../../../settings/presentation/widgets/reading_customization_sheet.dart';
import '../../data/parsing/formula_detector.dart';
import '../../data/parsing/pdf_page_locator.dart';
import '../../data/repositories/audio_tts_repository.dart';
import '../../data/repositories/device_tts_repository.dart';
import '../../data/repositories/tts/tts_capabilities.dart';
import '../../data/repositories/tts/voice_parser.dart';
import '../../data/repositories/tts_repository_proxy.dart';
import '../../domain/repositories/tts_repository.dart';
import '../../data/repositories/bookmark_repository.dart';
import '../../data/repositories/chapter_cache_repository.dart';
import '../../data/repositories/reading_stats_repository.dart';
import '../../domain/entities/bookmark.dart';
import '../../domain/entities/chapter_block.dart';
import '../../domain/repositories/reader_repository.dart';
import '../bloc/reader_bloc.dart';
import '../background/reading_audio_handler.dart';
import '../reading_focus_controller.dart';
import '../reading_typography.dart';
import '../widgets/formula_source_sheet.dart';
import '../bloc/reader_event.dart';
import '../bloc/reader_state.dart';
import '../widgets/ambient_sound_sheet.dart';
import '../widgets/book_search_delegate.dart';
import '../widgets/bookmarks_sheet.dart';
import '../widgets/pdf_crop_image.dart';
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
      child: _ReaderView(bookTitle: bookTitle, bookId: bookId),
    );
  }
}

class _ReaderView extends StatefulWidget {
  const _ReaderView({required this.bookTitle, required this.bookId});

  final String bookTitle;
  final String bookId;

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

  /// Contador de peticiones explícitas de re-centrado, que solo incrementa
  /// el botón "Volver a la lectura".
  ///
  /// Separado de [_followVoice] a propósito. Antes los párrafos escuchaban
  /// directamente `followVoice`, y como la lectura al pararse lo vuelve a
  /// poner en `true` para la próxima sesión, ese simple re-armado arrastraba
  /// la pantalla de vuelta a la voz aunque el usuario se hubiera ido a leer
  /// otra cosa por su cuenta. Un contador tampoco sufre el otro problema del
  /// notificador booleano: `ValueNotifier` no avisa si el valor no cambia, así
  /// que pulsar el botón estando ya enganchado no hacía nada.
  final ValueNotifier<int> _recenterRequests = ValueNotifier<int>(0);
  bool _showReturnButton = false;
  bool _streamsSubscribed = false;
  bool _disposed = false;

  /// El bloc del libro, guardado al montar. En `dispose()` el elemento ya
  /// está desmontado y `context.read` lanza: la excepción abortaba el
  /// desmontaje, el `BlocProvider` no cerraba el bloc y la voz seguía
  /// leyendo fuera del libro.
  late final ReaderBloc _bloc;

  /// Ruta del PDF de origen, cuando el libro se importó de uno. Habilita el
  /// botón que enseña la fórmula tal y como está maquetada en el libro.
  String? _pdfSourcePath;

  // Reading session tracking.
  final Stopwatch _sessionStopwatch = Stopwatch();
  int _sessionStartWordIndex = 0;
  StreamSubscription<TtsPlaybackStatus>? _ttsStatusSub;

  /// Modo concentración: pantalla completa y "No molestar" (ADR 12).
  late final ReadingFocusController _focus = ReadingFocusController(
    fullscreen: sl<SystemFullscreen>(),
    quietMode: sl<QuietMode>(),
    prefs: sl<FocusPrefs>(),
    askForQuietAccess: _askForQuietAccess,
    showDesktopQuietHint: _isWindows ? _showWindowsQuietHint : null,
  );

  /// Puente con los controles del sistema para seguir leyendo con la
  /// pantalla apagada (ADR 12). Es `null` donde no hay servicio de
  /// reproducción (todo lo que no es Android, o si no pudo arrancar): ahí la
  /// voz se sigue parando en segundo plano, como antes.
  ReadingAudioHandler? _audioHandler;

  static bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  late final PreferencesCubit _preferencesCubit = PreferencesCubit(
    repository: sl(),
  );

  void _toggleImmersive() => setState(() => _immersive = !_immersive);

  /// Entra o sale del modo concentración. El toque sobre el texto sigue
  /// alternando solo los controles del lector ([_toggleImmersive]); colgar de
  /// ahí el "No molestar" lo encendería y apagaría con cada toque.
  Future<void> _toggleFullscreen() async {
    if (_focus.isFullscreen) {
      await _focus.exit();
      if (!_disposed && mounted) setState(() => _immersive = false);
    } else {
      setState(() => _immersive = true);
      await _focus.enter();
      if (!_disposed && mounted) setState(() {});
    }
  }

  /// Pide el "Acceso a No molestar" la primera vez (ADR 12, sección 2).
  Future<QuietAccessChoice> _askForQuietAccess() async {
    if (_disposed || !mounted) return QuietAccessChoice.notNow;
    var dontAskAgain = false;
    final choice = await showDialog<QuietAccessChoice>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          icon: const Icon(Icons.do_not_disturb_on_rounded),
          title: const Text('Silenciar notificaciones mientras lees'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Para silenciar las notificaciones de otras apps en pantalla '
                'completa, LectorSync necesita el permiso "Acceso a No '
                'molestar". Se abrirá Ajustes: activa LectorSync y vuelve.\n\n'
                'Tus excepciones (favoritos, alarmas) se respetan y la voz '
                'sigue sonando.',
              ),
              CheckboxListTile(
                value: dontAskAgain,
                onChanged: (v) =>
                    setDialogState(() => dontAskAgain = v ?? false),
                title: const Text('No volver a preguntar'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                dontAskAgain
                    ? QuietAccessChoice.never
                    : QuietAccessChoice.notNow,
              ),
              child: const Text('Seguir sin silenciar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(QuietAccessChoice.openSettings),
              child: const Text('Abrir ajustes'),
            ),
          ],
        ),
      ),
    );
    return choice ?? QuietAccessChoice.notNow;
  }

  /// En Windows no hay API para silenciar, pero el sistema tiene su propia
  /// regla para la pantalla completa. Se avisa una sola vez (ADR 12).
  Future<void> _showWindowsQuietHint() async {
    if (_disposed || !mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.do_not_disturb_on_rounded),
        title: const Text('Silenciar Windows en pantalla completa'),
        content: const Text(
          'Windows puede activar No molestar por sí solo mientras una app '
          'está en pantalla completa. Se activa en Ajustes > Sistema > '
          'Notificaciones > "Activar No molestar automáticamente" > "Al usar '
          'una app en modo de pantalla completa".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Abrir ajustes'),
          ),
        ],
      ),
    );
    if (open != true) return;
    try {
      await launchUrl(Uri.parse('ms-settings:notifications'));
    } catch (_) {
      // Sin manejador para ms-settings: el texto ya explica dónde está.
    }
  }

  /// Conecta el libro abierto con la notificación de lectura (ADR 12).
  void _attachBackgroundReading() {
    if (!sl.isRegistered<ReadingAudioHandler>()) return;
    _audioHandler = sl<ReadingAudioHandler>()
      ..attach(
        bookId: widget.bookId,
        bookTitle: widget.bookTitle,
        commands: _BlocReadingCommands(context.read<ReaderBloc>()),
      );
  }
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

  /// Párrafo que contiene [wordIndex], o -1 si no se puede saber.
  int _findParagraphIndex(int wordIndex, List<int> wordOffsets) =>
      lastOffsetAtOrBefore(wordOffsets, wordIndex);

  /// Lleva la vista al párrafo que contiene [currentWordIndex].
  ///
  /// Devuelve `true` si el párrafo estaba localizado y el desplazamiento se
  /// puso en marcha. Quien ofrezca al usuario un control para volver a la
  /// lectura necesita saberlo: esconderlo tras un intento que no movió nada
  /// deja al lector perdido y sin forma de reintentar.
  bool _scrollToParagraph(int currentWordIndex) {
    if (!_followVoice.value) return false;
    final ctrl = _scrollController;
    if (ctrl == null || !ctrl.hasClients) return false;
    if (_wordOffsets.isEmpty || _paragraphKeys.isEmpty) return false;

    final paraIndex = _findParagraphIndex(currentWordIndex, _wordOffsets);
    if (paraIndex < 0 || paraIndex >= _paragraphKeys.length) return false;
    // Solo scrollear cuando cambia el párrafo activo, no en cada palabra.
    // Evita animaciones superpuestas que causan jitter/stutter.
    if (paraIndex == _lastScrolledParagraphIndex) return true;

    _lastScrolledParagraphIndex = paraIndex;

    final keyContext = _paragraphKeys[paraIndex].currentContext;
    if (keyContext != null) {
      Scrollable.ensureVisible(
        keyContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.3,
      );
      return true;
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
    return true;
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

    // Primero, el desplazamiento a nivel de PÁRRAFO, que es el que siempre
    // funciona: `_scrollToParagraph` ya cubre los dos casos —párrafo montado
    // (`ensureVisible`) y párrafo descartado por el ListView (salto
    // aproximado más corrección en el frame siguiente, usando su GlobalKey,
    // que existe siempre)—. Delegar solo en el re-centrado por oración dejaba
    // al usuario sin nada cuando el salto aterrizaba lejos del objetivo.
    final scrolled = _scrollToParagraph(idx);

    // Y después, el afinado a nivel de ORACIÓN para caer en la línea exacta.
    // Lo atiende el párrafo que contenga la palabra en curso.
    _recenterRequests.value++;

    // El botón solo se esconde si de verdad hubo a dónde ir. Escondiéndolo
    // siempre se llegaba a un callejón sin salida: con la voz ya parada,
    // `_onUserScroll` sale por `isTtsActive` y el botón no volvía a aparecer.
    if (scrolled && !_disposed && mounted) {
      setState(() => _showReturnButton = false);
    }
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
    // Por el proxy y no por `DeviceTtsRepository`: con la voz de servidor el
    // motor del dispositivo nunca emite `playing`, el cronómetro no arrancaba
    // y las sesiones de lectura no se registraban en las estadísticas. El
    // proxy reenvía el estado del motor que esté activo.
    _ttsStatusSub = sl<TtsRepository>().statusStream.listen((status) {
      // La misma señal decide el modo concentración y la notificación: si la
      // voz suena, el silencio sigue aunque la pantalla esté apagada.
      final voiceOn = status == TtsPlaybackStatus.playing ||
          status == TtsPlaybackStatus.loading;
      unawaited(_focus.setVoicePlaying(voiceOn));
      final handler = _audioHandler;
      if (handler != null) unawaited(handler.reportPlaying(voiceOn));

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
    _resolvePdfSource();
  }

  /// Averigua si el libro procede de un PDF que sigue en el dispositivo.
  ///
  /// Falla en silencio: no poder enseñar la página original es una función de
  /// más, nunca un motivo para estropear la lectura.
  Future<void> _resolvePdfSource() async {
    if (!sl.isRegistered<LocalBookStore>()) return;
    try {
      // Del widget y no del bloc: en initState el ReaderStarted acaba de
      // despacharse y el estado todavía tiene el bookId vacío.
      final path = await sl<LocalBookStore>().resolveStoredPath(widget.bookId);
      if (_disposed || !mounted) return;
      if (path == null || !path.toLowerCase().endsWith('.pdf')) return;
      setState(() => _pdfSourcePath = path);
    } catch (_) {
      // Catálogo no disponible o libro sin archivo local.
    }
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
      _bloc = context.read<ReaderBloc>();
      _listenEstimating();
      _listenTtsStatus();
      _attachBackgroundReading();
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
    // El modo concentración necesita saber si la app se ve en cualquier
    // transición, también al volver de Ajustes con el permiso concedido.
    final visible = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    unawaited(_focus.setAppVisible(visible));

    final shouldSave =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    // Con el servicio de reproducción enganchado, la voz sigue leyendo en
    // segundo plano (ADR 12): con la pantalla apagada o en otra app. Sin él,
    // se para como siempre, porque Android cortaría la lectura a medias.
    final shouldStopTts = state == AppLifecycleState.paused &&
        !(_audioHandler?.isAttached ?? false);

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
          (_bloc.state.currentWordIndex - _sessionStartWordIndex).abs();
      if (_sessionStopwatch.elapsed.inSeconds > 5 && wordsRead > 0) {
        sl<ReadingStatsRepository>().recordSession(
          bookId: _bloc.state.bookId,
          duration: _sessionStopwatch.elapsed,
          wordsRead: wordsRead,
        );
      }
    }
    _ttsStatusSub?.cancel();
    _estimatingSub?.cancel();
    // Cerrar el libro quita la pantalla completa, el "No molestar" y la
    // notificación de lectura.
    _focus.dispose();
    final handler = _audioHandler;
    if (handler != null) unawaited(handler.detach());
    _preferencesCubit.close();
    _scrollController?.dispose();
    _followVoice.dispose();
    _recenterRequests.dispose();
    super.dispose();
  }

  /// Lleva a la voz el ajuste "Leer los bloques de código en voz alta" y, si
  /// está sonando, la reinicia en la palabra actual para que el cambio se
  /// note al momento (ADR 13).
  void _applyReadCodeAloud(bool read) {
    if (!sl.isRegistered<DeviceTtsRepository>()) return;
    final tts = sl<DeviceTtsRepository>();
    if (tts.readCodeAloud == read) return;
    tts.readCodeAloud = read;
    if (_bloc.state.isTtsActive) _bloc.add(const ReaderTtsRestart());
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _preferencesCubit,
      child: BlocListener<PreferencesCubit, ReadingPreferences>(
        listenWhen: (prev, curr) => prev.readCodeAloud != curr.readCodeAloud,
        listener: (context, prefs) => _applyReadCodeAloud(prefs.readCodeAloud),
        child: BlocBuilder<PreferencesCubit, ReadingPreferences>(
          builder: (context, prefs) {
            final colors = ReadingPaletteColors.resolve(
              prefs.palette,
              Theme.of(context).colorScheme,
            );
            return PopScope(
              canPop: !_focus.isFullscreen,
              onPopInvokedWithResult: (didPop, _) {
                // Atrás saca primero de la pantalla completa en vez de
                // cerrar el libro (ADR 12).
                if (!didPop) unawaited(_toggleFullscreen());
              },
              child: _buildScaffold(context, prefs, colors),
            );
          },
        ),
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
        LogicalKeySet(LogicalKeyboardKey.f11): const _ToggleFullscreenIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape): const _ExitFullscreenIntent(),
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
          _ToggleFullscreenIntent: _CallbackAction(
            () => unawaited(_toggleFullscreen()),
          ),
          _ExitFullscreenIntent: _CallbackAction(() {
            if (_focus.isFullscreen) unawaited(_toggleFullscreen());
          }),
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
                  // Al darle al play la vista va a donde empieza a leer, sin
                  // esperar a que la voz cambie de párrafo.
                  if (curr.isTtsActive && !prev.isTtsActive) return true;
                  // Con voz o sin ella: mover la barra de posición, saltar a
                  // un marcador o aceptar el progreso de otro dispositivo
                  // también lleva la vista hasta la palabra.
                  if (prev.currentWordIndex != curr.currentWordIndex) {
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
                    _audioHandler?.updateChapter(chapter.title);
                    _lastScrolledParagraphIndex = -1;
                    final oldCtrl = _scrollController;
                    setState(() {
                      // Sin `keepScrollOffset`: el controlador nuevo recuperaba
                      // de PageStorage el desplazamiento del capítulo anterior,
                      // y el siguiente se abría a media pantalla.
                      _scrollController =
                          ScrollController(keepScrollOffset: false);
                    });
                    oldCtrl?.dispose();
                    // Al abrir el libro, la palabra guardada puede quedar lejos
                    // del principio del capítulo: la vista va hasta ella sin
                    // esperar a que suene la voz.
                    final target = state.currentWordIndex;
                    if (target > 0) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _scrollToParagraph(target);
                      });
                    }
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
                  // Primera apertura: se está extrayendo el texto del
                  // archivo y partiéndolo en capítulos. En un PDF largo son
                  // varios segundos, y merece la pena decir que solo pasa
                  // una vez en lugar de dejar un spinner mudo.
                  return LoadingView(
                    message: 'Preparando el libro',
                    detail: 'Se analiza el archivo y se divide en capítulos. '
                        'La próxima vez abrirá al instante.',
                    color: colors.foreground,
                  );
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

    final fullscreenBtn = IconButton(
      onPressed: () => unawaited(_toggleFullscreen()),
      icon: Icon(
        _focus.isFullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
      ),
      tooltip: _focus.isFullscreen
          ? 'Salir de pantalla completa${hint('F11')}'
          : 'Pantalla completa${hint('F11')}',
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
              case 'fullscreen':
                unawaited(_toggleFullscreen());
                break;
            }
          },
          itemBuilder: (_) => [
            ...const [
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
            PopupMenuItem<String>(
              value: 'fullscreen',
              child: ListTile(
                leading: Icon(
                  _focus.isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                ),
                title: Text(
                  _focus.isFullscreen
                      ? 'Salir de pantalla completa'
                      : 'Pantalla completa',
                ),
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
      fullscreenBtn,
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
      recenterRequests: _recenterRequests,
      onUserScroll: _onUserScroll,
      paragraphKeys: _paragraphKeys,
      onToggleImmersive: _toggleImmersive,
      onParagraphKeys: (keys) => _paragraphKeys = keys,
      onWordOffsets: _updateWordOffsets,
      onNavigateChapter: (dir) => _navigateChapter(context, dir),
      speedBarVisible: _speedBarVisible,
      onToggleSpeedBar: _toggleSpeedBar,
      isEstimatingProgress: _isEstimatingProgress,
      pdfSourcePath: _pdfSourcePath,
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
            recenterRequests: _recenterRequests,
            onUserScroll: _onUserScroll,
            paragraphKeys: _paragraphKeys,
            onToggleImmersive: _toggleImmersive,
            onParagraphKeys: (keys) => _paragraphKeys = keys,
            onWordOffsets: _updateWordOffsets,
            onNavigateChapter: (dir) => _navigateChapter(context, dir),
            speedBarVisible: _speedBarVisible,
            onToggleSpeedBar: _toggleSpeedBar,
            isEstimatingProgress: _isEstimatingProgress,
            pdfSourcePath: _pdfSourcePath,
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
            recenterRequests: _recenterRequests,
            onUserScroll: _onUserScroll,
            paragraphKeys: _paragraphKeys,
            onToggleImmersive: _toggleImmersive,
            onParagraphKeys: (keys) => _paragraphKeys = keys,
            onWordOffsets: _updateWordOffsets,
            onNavigateChapter: (dir) => _navigateChapter(context, dir),
            speedBarVisible: _speedBarVisible,
            onToggleSpeedBar: _toggleSpeedBar,
            isEstimatingProgress: _isEstimatingProgress,
            pdfSourcePath: _pdfSourcePath,
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
    required this.recenterRequests,
    required this.onUserScroll,
    required this.paragraphKeys,
    required this.onToggleImmersive,
    required this.onParagraphKeys,
    required this.onWordOffsets,
    required this.onNavigateChapter,
    required this.speedBarVisible,
    required this.onToggleSpeedBar,
    this.isEstimatingProgress = false,
    this.pdfSourcePath,
  });

  final ReaderState state;
  final ReadingPreferences prefs;
  final ReadingPaletteColors colors;
  final bool immersive;
  final ScrollController? scrollController;
  final ValueListenable<bool> followVoice;

  /// Peticiones explícitas de re-centrado del botón "Volver a la lectura".
  final ValueListenable<int> recenterRequests;
  final VoidCallback onUserScroll;
  final List<GlobalKey> paragraphKeys;
  final VoidCallback onToggleImmersive;
  final void Function(List<GlobalKey>) onParagraphKeys;
  final void Function(List<int>) onWordOffsets;
  final void Function(int) onNavigateChapter;
  final bool speedBarVisible;
  final VoidCallback onToggleSpeedBar;
  final bool isEstimatingProgress;

  /// Ruta del PDF original, si el libro vino de uno. Habilita el botón
  /// "Ver en el libro" de los bloques de fórmula.
  final String? pdfSourcePath;

  @override
  State<_ReaderBody> createState() => _ReaderBodyState();
}

class _ReaderBodyState extends State<_ReaderBody> {
  String? _cachedChapterId;
  List<String> _cachedParagraphs = const [];

  /// Bloques del capítulo (ADR 13): uno por elemento de la lista, en lugar de
  /// un párrafo por elemento. Vacío en los capítulos sin maquetación.
  List<ChapterBlock> _cachedBlocks = const [];
  List<int> _cachedWordOffsets = const [];
  List<GlobalKey> _cachedKeys = const [];
  List<bool> _cachedFormulas = const [];
  int _cachedChapterWordMax = 0;

  /// Vive en el State y no en cada bloque de fórmula: el índice de páginas
  /// del PDF se construye una vez y lo comparten todas las fórmulas del libro.
  final PdfPageLocator _pageLocator = PdfPageLocator();

  void _showFormulaSource(BuildContext context, String fragment) {
    final path = widget.pdfSourcePath;
    if (path == null) return;
    FormulaSourceSheet.show(
      context,
      pdfPath: path,
      fragment: fragment,
      locator: _pageLocator,
    );
  }

  /// "Ver en el libro" de una figura: su página ya se conoce, no hay que
  /// buscarla por el texto.
  void _showFigureSource(BuildContext context, ChapterBlock block) {
    final path = widget.pdfSourcePath;
    if (path == null || block.page == null) return;
    FormulaSourceSheet.show(
      context,
      pdfPath: path,
      fragment: block.text,
      locator: _pageLocator,
      pageIndex: block.page,
      title: block.figureKind == FigureKind.formula
          ? 'Fórmula en el libro'
          : 'Figura en el libro',
    );
  }

  @override
  void dispose() {
    _pageLocator.clear();
    unawaited(PdfCropCache.instance.clear());
    super.dispose();
  }

  void _recomputeIfNeeded() {
    final chapter = widget.state.currentChapter;
    if (chapter == null) return;
    if (chapter.id == _cachedChapterId) return;

    final blocks = chapter.blocks;
    final List<String> paragraphs;
    final offsets = <int>[];
    if (blocks.isNotEmpty) {
      // Con maquetación, un elemento por bloque: partir el texto por líneas
      // en blanco rompería el código, que las lleva dentro.
      paragraphs = [for (final b in blocks) b.text];
      var cursor = 0;
      for (final block in blocks) {
        offsets.add(cursor);
        cursor += block.wordCount;
      }
      // La heurística de fórmulas solo es para los capítulos sin bloques:
      // aquí enmarcaba hasta los teléfonos de la página de créditos.
      _cachedFormulas = const [];
    } else {
      paragraphs = chapter.paragraphs.isEmpty
          ? <String>[chapter.text ?? '']
          : chapter.paragraphs;
      var cursor = 0;
      for (final para in paragraphs) {
        offsets.add(cursor);
        cursor += para.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      }
      // Se calcula una vez por capítulo: el itemBuilder del ListView corre
      // en cada frame de scroll y no puede pagar la heurística por párrafo.
      _cachedFormulas =
          paragraphs.map(looksLikeFormula).toList(growable: false);
    }
    _cachedChapterId = chapter.id;
    _cachedParagraphs = paragraphs;
    _cachedBlocks = blocks;
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
    final blocks = _cachedBlocks;
    final wordOffsets = _cachedWordOffsets;
    final paragraphKeys = _cachedKeys;
    final formulas = _cachedFormulas;
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
            // Cambio de capítulo. El texto anterior sigue en pantalla, así
            // que basta una barra fina: sustituirlo por un spinner a
            // pantalla completa durante medio segundo daría un parpadeo
            // peor que la propia espera. Antes no se mostraba NADA, porque
            // la guarda de arriba exige `currentChapter == null` y al
            // cambiar de capítulo el anterior sigue puesto.
            BlocBuilder<ReaderBloc, ReaderState>(
              buildWhen: (prev, curr) => prev.status != curr.status,
              builder: (context, s) => LoadingBar(
                visible: s.status == ReaderStatus.loading,
                color: colors.accent,
              ),
            ),
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
                        // Con el capítulo en la clave, cada capítulo estrena
                        // posición de desplazamiento. Solo con el controlador
                        // nuevo no bastaba: la posición nueva absorbe la vieja
                        // y el capítulo siguiente se abría a media pantalla.
                        key: ValueKey('${prefs.fontFamilyName}|${chapter.id}'),
                        controller: widget.scrollController,
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        itemCount: paragraphs.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            final chapter = widget.state.currentChapter;
                            return _EditorialChapterHeader(
                              chapterNumber:
                                  widget.state.currentChapterIndex + 1,
                              chapterTitle: chapter == null
                                  ? ''
                                  : chapterHeaderTitle(
                                      chapter.title, chapter.text ?? ''),
                              foreground: colors.foreground,
                              bodyFontSize: prefs.fontSize,
                              fontFamily: prefs.fontFamilyName,
                            );
                          }
                          final paraIndex = index - 1;
                          final endIdx = (paraIndex + 1 < wordOffsets.length)
                              ? wordOffsets[paraIndex + 1] - 1
                              : chapterWordMax - 1;
                          final itemKey = paraIndex < paragraphKeys.length
                              ? paragraphKeys[paraIndex]
                              : null;
                          final block = paraIndex < blocks.length
                              ? blocks[paraIndex]
                              : null;
                          if (block != null &&
                              (block.kind == ChapterBlockKind.code ||
                                  block.kind == ChapterBlockKind.figure)) {
                            return _WholeBlockHighlight(
                              key: itemKey,
                              followVoice: widget.followVoice,
                              recenterRequests: widget.recenterRequests,
                              startWordIndex: wordOffsets[paraIndex],
                              endWordIndex: endIdx,
                              builder: (context, active) =>
                                  block.kind == ChapterBlockKind.code
                                      ? _CodeBlockView(
                                          code: block.text,
                                          textStyle: textStyle,
                                          accentColor: colors.accent,
                                          active: active,
                                        )
                                      : _FigureBlockView(
                                          block: block,
                                          pdfPath: widget.pdfSourcePath,
                                          bodyFontSize: prefs.fontSize,
                                          inkColor: colors.foreground,
                                          accentColor: colors.accent,
                                          active: active,
                                          onViewSource: () =>
                                              _showFigureSource(context, block),
                                        ),
                            );
                          }
                          return _ParagraphHighlightProxy(
                            key: itemKey,
                            followVoice: widget.followVoice,
                            recenterRequests: widget.recenterRequests,
                            paragraph: paragraphs[paraIndex],
                            startWordIndex: wordOffsets[paraIndex],
                            endWordIndex: endIdx,
                            textStyle: textStyle,
                            accentColor: colors.accent,
                            isFirstParagraph: paraIndex == 0,
                            isHeading: block?.kind == ChapterBlockKind.heading,
                            isFormula: paraIndex < formulas.length &&
                                formulas[paraIndex],
                            bodyTextAlign: prefs.textAlign,
                            onViewSource: widget.pdfSourcePath == null
                                ? null
                                : () => _showFormulaSource(
                                      context,
                                      paragraphs[paraIndex],
                                    ),
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

final RegExp _notAlphanumeric = RegExp(r'[^\p{L}\p{N}]', unicode: true);

/// Título del encabezado del capítulo: vacío si el texto ya empieza por él.
///
/// En un TXT o un Markdown la línea "Capítulo 1" es parte del texto y además
/// da título al capítulo. Se quita del encabezado y no del texto: de ahí la
/// lee la voz, y quitarla movería las posiciones de lectura guardadas.
@visibleForTesting
String chapterHeaderTitle(String title, String text) {
  String key(String s) => s.toLowerCase().replaceAll(_notAlphanumeric, '');
  final firstLine = text.trimLeft().split('\n').first;
  return key(firstLine) == key(title) ? '' : title;
}

class _EditorialChapterHeader extends StatelessWidget {
  const _EditorialChapterHeader({
    required this.chapterNumber,
    required this.chapterTitle,
    required this.foreground,
    this.bodyFontSize = 18.0,
    this.fontFamily,
  });

  final int chapterNumber;
  final String chapterTitle;
  final Color foreground;

  /// Tamaño del cuerpo de texto. La jerarquía del encabezado se deriva de
  /// él en vez de usar tamaños fijos: con la fuente al máximo, un título
  /// clavado en 20 px acababa siendo **más pequeño** que el propio texto.
  final double bodyFontSize;

  /// Familia del cuerpo, para que el título no salga en otra tipografía.
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    // El aire alrededor también crece con el texto: márgenes fijos con
    // fuente grande hacen que el título se pegue al primer párrafo.
    final gap = bodyFontSize * 0.7;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, bodyFontSize * 1.4, 24, bodyFontSize * 1.8),
      child: Column(
        children: [
          Text(
            '$chapterNumber',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: chapterNumberSize(bodyFontSize),
              fontWeight: FontWeight.w700,
              fontFamily: fontFamily,
              color: foreground,
              height: 1.2,
            ),
          ),
          SizedBox(height: gap),
          SizedBox(
            width: 60,
            child: Divider(
              height: 1,
              thickness: 1,
              color: foreground.withValues(alpha: 0.3),
            ),
          ),
          if (chapterTitle.isNotEmpty) ...[
            SizedBox(height: gap),
            Text(
              chapterTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: chapterTitleSize(bodyFontSize),
                fontWeight: FontWeight.w500,
                fontFamily: fontFamily,
                color: foreground.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ],
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
    required this.recenterRequests,
    required this.paragraph,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.textStyle,
    this.accentColor,
    this.isFirstParagraph = false,
    this.isHeading = false,
    this.isFormula = false,
    this.onViewSource,
    this.bodyTextAlign = TextAlign.justify,
    super.key,
  });

  final ValueListenable<bool> followVoice;

  /// Peticiones explícitas de re-centrado del botón "Volver a la lectura".
  final ValueListenable<int> recenterRequests;
  final String paragraph;
  final int startWordIndex;
  final int endWordIndex;
  final TextStyle textStyle;
  final Color? accentColor;
  final bool isFirstParagraph;

  /// Título de sección o rótulo de ejercicio (ADR 13): algo más grande, en
  /// seminegrita, sin sangría y con aire encima. Se resalta igual que un
  /// párrafo cuando la voz lo lee.
  final bool isHeading;

  /// El párrafo es una fórmula aplanada por el extractor de PDF.
  ///
  /// Solo cambia cómo se presenta: justificar y sangrar una tira de símbolos
  /// la vuelve ilegible. El resaltado y el auto-scroll siguen funcionando
  /// igual, así que no hay riesgo de regresión en el seguidor de voz.
  final bool isFormula;

  /// Abre la página original del PDF donde está esta fórmula. Solo se pasa
  /// cuando [isFormula] y el libro procede de un PDF.
  final VoidCallback? onViewSource;

  /// Alineación elegida por el lector en sus preferencias.
  ///
  /// Antes estaba clavada a `justify` aquí dentro, así que el interruptor
  /// "Justificar texto" del panel de ajustes se guardaba, se persistía y no
  /// producía ningún efecto visible.
  final TextAlign bodyTextAlign;

  @override
  State<_ParagraphHighlightProxy> createState() =>
      _ParagraphHighlightProxyState();
}

class _ParagraphHighlightProxyState extends State<_ParagraphHighlightProxy> {
  static final _sentenceEnd = RegExp(r'(?<=[.!?…])\s+');
  static final _wsRegex = RegExp(r'\s+');

  late List<_Sentence> _sentences;
  late List<GlobalKey> _sentenceKeys;

  /// Segunda pasada del re-centrado. Se guarda para poder cancelarla en
  /// [dispose] y no retener el State 320 ms de más.
  Timer? _recenterTimer;

  @override
  void initState() {
    super.initState();
    _sentences = _splitSentences();
    widget.recenterRequests.addListener(_onRecenterRequested);
  }

  @override
  void dispose() {
    widget.recenterRequests.removeListener(_onRecenterRequested);
    // El temporizador captura `this`: sin cancelarlo, cada párrafo desmontado
    // sobrevivía 320 ms con sus oraciones y sus GlobalKey. En un fling eso son
    // varias decenas de States muertos vivos a la vez.
    _recenterTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ParagraphHighlightProxy old) {
    super.didUpdateWidget(old);
    if (old.recenterRequests != widget.recenterRequests) {
      old.recenterRequests.removeListener(_onRecenterRequested);
      widget.recenterRequests.addListener(_onRecenterRequested);
    }
    if (old.paragraph != widget.paragraph ||
        old.startWordIndex != widget.startWordIndex) {
      _sentences = _splitSentences();
    }
  }

  void _onRecenterRequested() => _recenterActiveSentence();

  /// Centra la ORACIÓN que contiene la palabra en curso, solo si pertenece a
  /// este párrafo. Lo dispara el botón "Volver a la lectura" para atinar a la
  /// línea que se está leyendo, no solo al inicio del párrafo.
  void _recenterActiveSentence() {
    if (!widget.followVoice.value) return;

    // Descarte barato ANTES de programar nada: son dos comparaciones y dejan
    // fuera a todos los párrafos menos uno. Hacerlo dentro de los callbacks
    // significaba programar un post-frame y un temporizador de 320 ms por
    // cada párrafo montado para tirarlos justo después.
    final active = _activeSentenceIndex(
      context.read<ReaderBloc>().state.currentWordIndex,
    );
    if (active < 0 || active >= _sentenceKeys.length) return;

    void doScroll() {
      if (!mounted || !widget.followVoice.value) return;
      final idx = _activeSentenceIndex(
        context.read<ReaderBloc>().state.currentWordIndex,
      );
      if (idx < 0 || idx >= _sentenceKeys.length) return;
      final keyCtx = _sentenceKeys[idx].currentContext;
      if (keyCtx == null) return;
      Scrollable.ensureVisible(
        keyCtx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.3,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      doScroll();
      // Segunda pasada tras la primera animación: si el layout aún se estaba
      // asentando (p. ej. tras un salto grande), el primer ensureVisible
      // queda impreciso. Repetir con el layout ya estable evita tener que
      // pulsar el botón dos veces. Si el primero ya acertó, este no mueve nada.
      _recenterTimer?.cancel();
      _recenterTimer = Timer(const Duration(milliseconds: 320), doScroll);
    });
  }

  /// Una "oración" que solo es un número o una abreviatura ("1.", "a.",
  /// "Fig.", "pág.") no va aparte: el "1." de una lista numerada quedaba en
  /// una línea suelta y el resto del elemento debajo.
  static final _shortStop = RegExp(r'^(\d{1,3}|[a-zA-ZáéíóúñÁÉÍÓÚÑ]{1,4})\.$');

  List<_Sentence> _splitSentences() {
    final parts = <String>[];
    for (final part in widget.paragraph.split(_sentenceEnd)) {
      if (parts.isNotEmpty && _shortStop.hasMatch(parts.last.trim())) {
        parts[parts.length - 1] = '${parts.last} $part';
      } else {
        parts.add(part);
      }
    }
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
    final indentWidth = widget.isHeading
        ? 0.0
        : paragraphIndent(
            fontSize: widget.textStyle.fontSize ?? 18.0,
            isFirstParagraph: widget.isFirstParagraph,
            isFormula: widget.isFormula,
          );
    // Una fórmula no se justifica: separar los símbolos para cuadrar el
    // margen es justo lo que la vuelve ilegible. Un título tampoco.
    final textAlign = widget.isFormula
        ? TextAlign.center
        : widget.isHeading
            ? TextAlign.start
            : widget.bodyTextAlign;
    final textStyle = widget.isHeading
        ? widget.textStyle.copyWith(
            fontSize: (widget.textStyle.fontSize ?? 18.0) * 1.15,
            fontWeight: FontWeight.w600,
            height: 1.3,
          )
        : widget.isFormula
        ? widget.textStyle.copyWith(
            // Sin assets propios: caemos en la monoespaciada del sistema, que
            // alinea exponentes y paréntesis mucho mejor que la de lectura.
            //
            // Tiene que ir explícita: `copyWith` resuelve cada campo como
            // `valor ?? this.valor`, así que pasar `null` CONSERVABA la
            // familia de lectura y el bloque nunca cambiaba de tipografía.
            // Y `fontFamilyFallback` por sí solo tampoco basta: solo entra
            // para glifos que falten en la familia principal, y los dígitos
            // y paréntesis están en todas.
            fontFamily: 'monospace',
            fontFamilyFallback: const [
              'Menlo',
              'Consolas',
              'Courier New',
            ],
            height: 1.5,
          )
        : widget.textStyle;

    final padding = EdgeInsets.only(
      left: 12,
      right: 12,
      top: widget.isFirstParagraph
          ? 0
          : widget.isHeading
              ? 20
              : (widget.isFormula ? 12 : 4),
      bottom: widget.isFormula ? 12 : (widget.isHeading ? 8 : 4),
    );

    if (_sentences.isEmpty) {
      return Padding(
        padding: padding,
        child: Text(
          widget.paragraph,
          textAlign: textAlign,
          style: textStyle,
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

          final body = Column(
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
                  // La sangría va dentro del texto, como un hueco al principio:
                  // en una fila con el texto al lado se sangraba la oración
                  // entera, y un párrafo de una sola oración salía desplazado
                  // de arriba abajo.
                  child: i == 0 && indentWidth > 0
                      ? Text.rich(
                          TextSpan(
                            children: [
                              WidgetSpan(child: SizedBox(width: indentWidth)),
                              TextSpan(text: _sentences[i].text),
                            ],
                          ),
                          textAlign: textAlign,
                          style: textStyle,
                        )
                      : Text(
                          _sentences[i].text,
                          textAlign: textAlign,
                          style: textStyle,
                        ),
                ),
            ],
          );

          return Padding(
            padding: padding,
            child: widget.isFormula
                ? _FormulaFrame(
                    accentColor: widget.accentColor,
                    onViewSource: widget.onViewSource,
                    child: body,
                  )
                : body,
          );
        },
      ),
    );
  }
}

/// Marco visual de un bloque de fórmula.
///
/// Separa la ecuación de la prosa que la rodea con un filete lateral y un
/// fondo apenas teñido: el objetivo es que el ojo la localice de un vistazo
/// sin que compita con el texto en contraste.
class _FormulaFrame extends StatelessWidget {
  const _FormulaFrame({required this.child, this.accentColor, this.onViewSource});

  final Widget child;
  final Color? accentColor;

  /// Abre la página original del PDF. Es `null` cuando el libro no viene de
  /// un PDF y por tanto no hay página que enseñar.
  final VoidCallback? onViewSource;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: accent.withValues(alpha: 0.45), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          if (onViewSource != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onViewSource,
                icon: const Icon(Icons.image_search_rounded, size: 18),
                label: const Text('Ver en el libro'),
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Resalta un bloque entero mientras la voz pasa por él y lo mantiene a la
/// vista, como hace [_ParagraphHighlightProxy] con cada oración (ADR 13).
///
/// Es para el código y las figuras: no se parten en oraciones, y resaltar
/// palabra a palabra un listado o un recorte no tendría sentido.
class _WholeBlockHighlight extends StatefulWidget {
  const _WholeBlockHighlight({
    required this.followVoice,
    required this.recenterRequests,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.builder,
    super.key,
  });

  final ValueListenable<bool> followVoice;

  /// Peticiones explícitas de re-centrado del botón "Volver a la lectura".
  final ValueListenable<int> recenterRequests;
  final int startWordIndex;
  final int endWordIndex;
  final Widget Function(BuildContext context, bool active) builder;

  @override
  State<_WholeBlockHighlight> createState() => _WholeBlockHighlightState();
}

class _WholeBlockHighlightState extends State<_WholeBlockHighlight> {
  /// Segunda pasada del re-centrado, cancelable en [dispose] como en
  /// [_ParagraphHighlightProxyState].
  Timer? _recenterTimer;

  bool _isActive(ReaderState s) =>
      s.isTtsActive &&
      s.currentWordIndex >= widget.startWordIndex &&
      s.currentWordIndex <= widget.endWordIndex;

  @override
  void initState() {
    super.initState();
    widget.recenterRequests.addListener(_onRecenterRequested);
  }

  @override
  void didUpdateWidget(covariant _WholeBlockHighlight old) {
    super.didUpdateWidget(old);
    if (old.recenterRequests != widget.recenterRequests) {
      old.recenterRequests.removeListener(_onRecenterRequested);
      widget.recenterRequests.addListener(_onRecenterRequested);
    }
  }

  @override
  void dispose() {
    widget.recenterRequests.removeListener(_onRecenterRequested);
    _recenterTimer?.cancel();
    super.dispose();
  }

  void _onRecenterRequested() {
    if (!widget.followVoice.value) return;
    if (!_isActive(context.read<ReaderBloc>().state)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureVisible();
      _recenterTimer?.cancel();
      _recenterTimer =
          Timer(const Duration(milliseconds: 320), _ensureVisible);
    });
  }

  void _ensureVisible() {
    if (!mounted || !widget.followVoice.value) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: 0.3,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: BlocConsumer<ReaderBloc, ReaderState>(
        listenWhen: (prev, curr) => _isActive(curr) && !_isActive(prev),
        listener: (context, state) {
          if (!widget.followVoice.value) return;
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _ensureVisible());
        },
        buildWhen: (prev, curr) => _isActive(prev) != _isActive(curr),
        builder: (context, state) => widget.builder(context, _isActive(state)),
      ),
    );
  }
}

/// Bloque de código: monoespaciada, un poco más pequeña que el cuerpo, en un
/// panel con filete lateral (ADR 13).
///
/// Las líneas largas **no se parten**: el bloque se desplaza en horizontal.
/// Partirlas rompería la sangría, que en Python es sintaxis.
class _CodeBlockView extends StatelessWidget {
  const _CodeBlockView({
    required this.code,
    required this.textStyle,
    required this.active,
    this.accentColor,
  });

  final String code;
  final TextStyle textStyle;
  final bool active;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    final style = textStyle.copyWith(
      // Explícita: `copyWith` con `null` conservaría la familia de lectura
      // (la misma trampa que en las fórmulas, ver ADR §7).
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      fontSize: (textStyle.fontSize ?? 18.0) * 0.82,
      height: 1.45,
      letterSpacing: 0,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: active ? 0.12 : 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: accent.withValues(alpha: 0.45), width: 3),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: math.max(0.0, constraints.maxWidth - 24),
              ),
              child: Text(code, style: style, softWrap: false),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ecuación o figura recortada del PDF original (ADR 13).
///
/// Se pinta a la escala de la letra: la altura de la letra del libro pasa a
/// ser la que eligió el lector, así que una ecuación sale del tamaño del
/// texto que la rodea en vez de estirada al ancho de la columna. Si no cabe,
/// se reduce hasta el ancho de la columna.
///
/// Las fórmulas toman el color del texto sobre fondo transparente, para que
/// se lean igual en todos los temas; las figuras grandes se enseñan tal cual,
/// con las esquinas redondeadas. Al tocarlo se abre la página en el libro.
class _FigureBlockView extends StatelessWidget {
  const _FigureBlockView({
    required this.block,
    required this.pdfPath,
    required this.bodyFontSize,
    required this.inkColor,
    required this.active,
    required this.onViewSource,
    this.accentColor,
  });

  final ChapterBlock block;
  final String? pdfPath;
  final double bodyFontSize;
  final Color inkColor;
  final bool active;
  final VoidCallback onViewSource;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final rect = block.rect!;
    final isFormula = block.figureKind == FigureKind.formula;
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    final pointsToPixels = bodyFontSize / (block.textHeight ?? 11);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = math.max(1.0, constraints.maxWidth - 16);
          final width = math.min(rect.width * pointsToPixels, available);
          final height = width * rect.height / rect.width;
          final path = pdfPath;
          Widget image = path == null
              ? SizedBox(width: width, height: height)
              : PdfCropImage(
                  pdfPath: path,
                  pageIndex: block.page!,
                  rect: rect,
                  width: width,
                  height: height,
                );
          image = isFormula
              ? ColorFiltered(colorFilter: _inkFilter(inkColor), child: image)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: image,
                );
          return Semantics(
            button: true,
            label: isFormula ? 'Fórmula' : 'Figura',
            hint: 'Ver en el libro',
            child: GestureDetector(
              onTap: onViewSource,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: active
                      ? accent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: image),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Pinta la tinta con [ink] y deja el papel transparente: la opacidad sale
  /// de lo oscuro que es cada píxel. En vez de invertir la imagen en los temas
  /// oscuros, la fórmula queda del color del texto en cualquier paleta, sepia
  /// incluida, donde invertir pondría un recuadro negro sobre fondo claro.
  ///
  /// La opacidad es `A·(1 − luminancia)` y el color, el de la tinta
  /// multiplicado por esa opacidad, **sin columna de traslación**. Con una
  /// constante ("255 menos la luminancia") lo transparente salía opaco:
  /// Impeller filtra una capa más grande que la imagen y en el Pixel la
  /// pantalla se cubría de un rectángulo del color del texto. Y como filtra
  /// en color premultiplicado, el color tiene que ir ya multiplicado.
  static ColorFilter _inkFilter(Color ink) {
    final r = ink.r, g = ink.g, b = ink.b;
    return ColorFilter.matrix(<double>[
      -0.299 * r, -0.587 * r, -0.114 * r, r, 0, //
      -0.299 * g, -0.587 * g, -0.114 * g, g, 0,
      -0.299 * b, -0.587 * b, -0.114 * b, b, 0,
      -0.299, -0.587, -0.114, 1, 0,
    ]);
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

class _ToggleFullscreenIntent extends Intent {
  const _ToggleFullscreenIntent();
}

class _ExitFullscreenIntent extends Intent {
  const _ExitFullscreenIntent();
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
    final network = voiceNeedsNetwork(v) ? 'Necesita internet' : '';
    final parts = [
      locale,
      gender,
      neural,
      network,
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
                    child: LoadingView(message: 'Buscando voces instaladas'),
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
                        voiceNeedsNetwork(v)
                            ? Icons.cloud_outlined
                            : _isNeuralVoice(v)
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

/// Órdenes de los controles del sistema (notificación, pantalla de bloqueo,
/// auriculares) traducidas a eventos del lector (ADR 12). Pausar es parar y
/// reanudar desde la palabra en curso, que es como pausa el lector.
class _BlocReadingCommands implements ReadingCommands {
  _BlocReadingCommands(this._bloc);

  final ReaderBloc _bloc;

  @override
  Future<void> play() async {
    if (_bloc.isClosed) return;
    final state = _bloc.state;
    final hasText = state.currentChapter?.words.isNotEmpty ?? false;
    if (!state.isTtsActive && hasText) _bloc.add(const ReaderTtsToggled());
  }

  @override
  Future<void> pause() async {
    if (_bloc.isClosed) return;
    if (_bloc.state.isTtsActive) _bloc.add(const ReaderTtsToggled());
  }
}
