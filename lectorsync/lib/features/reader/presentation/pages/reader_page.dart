import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../settings/domain/entities/reading_preferences.dart';
import '../../../settings/presentation/cubit/preferences_cubit.dart';
import '../../../settings/presentation/widgets/reading_customization_sheet.dart';
import '../../data/repositories/audio_tts_repository.dart';
import '../../data/repositories/device_tts_repository.dart';
import '../../data/repositories/tts/tts_capabilities.dart';
import '../../data/repositories/tts_repository_proxy.dart';
import '../../domain/repositories/tts_repository.dart';
import '../bloc/reader_bloc.dart';
import '../bloc/reader_event.dart';
import '../bloc/reader_state.dart';

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
      create: (_) => ReaderBloc(
        readerRepository: sl(),
        ttsRepository: sl(),
        audioTtsRepository:
            sl.isRegistered<AudioTtsRepository>() ? sl<AudioTtsRepository>() : null,
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

class _ReaderViewState extends State<_ReaderView> {
  ScrollController? _scrollController;
  List<GlobalKey> _paragraphKeys = [];
  List<int> _wordOffsets = [];
  int _lastScrolledParagraphIndex = -1;
  String? _lastChapterId;
  bool _immersive = false;
  bool _tocVisible = false;
  bool _isEstimatingProgress = false;
  StreamSubscription<bool>? _estimatingSub;

  late final PreferencesCubit _preferencesCubit = PreferencesCubit(repository: sl());

  void _toggleImmersive() => setState(() => _immersive = !_immersive);
  void _toggleToc() => setState(() => _tocVisible = !_tocVisible);

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
    if (_scrollController == null || !_scrollController!.hasClients) return;
    if (_wordOffsets.isEmpty || _paragraphKeys.isEmpty) return;

    final paraIndex = _findParagraphIndex(currentWordIndex, _wordOffsets);
    if (paraIndex < 0 || paraIndex >= _paragraphKeys.length) return;
    // Solo scrollear cuando cambia el párrafo activo, no en cada palabra.
    // Evita animaciones superpuestas que causan jitter/stutter.
    if (paraIndex == _lastScrolledParagraphIndex) return;

    _lastScrolledParagraphIndex = paraIndex;

    final keyContext = _paragraphKeys[paraIndex].currentContext;
    if (keyContext == null) return;

    Scrollable.ensureVisible(
      keyContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: 0.3,
    );
  }

  void _updateWordOffsets(List<int> offsets) {
    _wordOffsets = offsets;
  }

  void _listenEstimating() {
    _estimatingSub?.cancel();
    _estimatingSub = sl<DeviceTtsRepository>().estimatingStream.listen((v) {
      if (mounted) setState(() => _isEstimatingProgress = v);
    });
  }

  @override
  void dispose() {
    _estimatingSub?.cancel();
    _preferencesCubit.close();
    _scrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _estimatingSub ??= (() {
      _listenEstimating();
      return _estimatingSub;
    })();
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
        LogicalKeySet(LogicalKeyboardKey.arrowRight): const _NextChapterIntent(),
        LogicalKeySet(LogicalKeyboardKey.keyT): const _ToggleTocIntent(),
      },
      child: Actions(
        actions: <Type, Action>{
          _PlayPauseIntent: _CallbackAction(() {
          final state = context.read<ReaderBloc>().state;
          final hasText = state.currentChapter?.words.isNotEmpty ?? false;
          if (hasText) context.read<ReaderBloc>().add(const ReaderTtsToggled());
        }),
          _PrevChapterIntent: _CallbackAction(() => _navigateChapter(context, -1)),
          _NextChapterIntent: _CallbackAction(() => _navigateChapter(context, 1)),
          _ToggleTocIntent: _CallbackAction(_toggleToc),
        },
        child: Scaffold(
          backgroundColor: colors.background,
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
                  actions: [
                    if (bp.isExpanded)
                      IconButton(
                        onPressed: _toggleToc,
                        icon: Icon(_tocVisible
                            ? Icons.menu_book_rounded
                            : Icons.menu_book_outlined),
                        tooltip: 'Índice',
                      ),
                    if (bp.isMedium)
                      IconButton(
                        onPressed: _toggleToc,
                        icon: const Icon(Icons.list_rounded),
                        tooltip: 'Índice',
                      ),
                    IconButton(
                      onPressed: _openVoiceMenu,
                      icon: const Icon(Icons.record_voice_over_rounded),
                      tooltip: 'Voz',
                    ),
                    IconButton(
                      onPressed: _openCustomizationSheet,
                      icon: const Icon(Icons.tune_rounded),
                      tooltip: 'Personalizar',
                    ),
                    BlocBuilder<ReaderBloc, ReaderState>(
                      buildWhen: (prev, curr) =>
                          prev.ttsStatus != curr.ttsStatus ||
                          prev.currentChapter?.id != curr.currentChapter?.id,
                      builder: (context, state) {
                        final hasText = state.currentChapter?.words.isNotEmpty ?? false;
                        return IconButton(
                          onPressed: hasText
                              ? () =>
                                  context.read<ReaderBloc>().add(const ReaderTtsToggled())
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
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
          drawer: bp.isCompact
              ? Drawer(
                  child: SafeArea(
                    child: _ChapterList(bookTitle: widget.bookTitle),
                  ),
                )
              : null,
      body: BlocListener<ReaderBloc, ReaderState>(
        listenWhen: (prev, curr) {
          if (prev.currentChapter?.id != curr.currentChapter?.id &&
              curr.currentChapter != null) {
            return true;
          }
          if (curr.isTtsActive &&
              prev.currentWordIndex != curr.currentWordIndex) {
            final prevPara =
                _findParagraphIndex(prev.currentWordIndex, _wordOffsets);
            final currPara =
                _findParagraphIndex(curr.currentWordIndex, _wordOffsets);
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
            child: BlocConsumer<ReaderBloc, ReaderState>(
              listenWhen: (prev, curr) =>
                  curr.errorMessage != null && prev.errorMessage != curr.errorMessage,
              listener: (context, state) {
                final message = state.errorMessage;
                if (message == null) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(message)));
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
                  compact: () => _buildCompactBody(context, state, prefs, colors),
                  medium: () => _buildMediumBody(context, state, prefs, colors),
                  expanded: () => _buildExpandedBody(context, state, prefs, colors),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _navigateChapter(BuildContext context, int direction) {
    final state = context.read<ReaderBloc>().state;
    final newIndex = state.currentChapterIndex + direction;
    if (newIndex < 0 || newIndex >= state.chapters.length) return;
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
      paragraphKeys: _paragraphKeys,
      onToggleImmersive: _toggleImmersive,
      onParagraphKeys: (keys) => _paragraphKeys = keys,
      onWordOffsets: _updateWordOffsets,
      onNavigateChapter: (dir) => _navigateChapter(context, dir),
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
        if (_tocVisible) VerticalDivider(width: 1, color: scheme.outlineVariant),
    Expanded(
      child: _ReaderBody(
        state: state,
        prefs: prefs,
        colors: colors,
        immersive: _immersive,
        scrollController: _scrollController,
        paragraphKeys: _paragraphKeys,
        onToggleImmersive: _toggleImmersive,
        onParagraphKeys: (keys) => _paragraphKeys = keys,
        onWordOffsets: _updateWordOffsets,
        onNavigateChapter: (dir) => _navigateChapter(context, dir),
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
        if (_tocVisible) VerticalDivider(width: 1, color: scheme.outlineVariant),
    Expanded(
      flex: 3,
      child: _ReaderBody(
        state: state,
        prefs: prefs,
        colors: colors,
        immersive: _immersive,
        scrollController: _scrollController,
        paragraphKeys: _paragraphKeys,
        onToggleImmersive: _toggleImmersive,
        onParagraphKeys: (keys) => _paragraphKeys = keys,
        onWordOffsets: _updateWordOffsets,
        onNavigateChapter: (dir) => _navigateChapter(context, dir),
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
          prev.chapters != curr.chapters || prev.currentChapterIndex != curr.currentChapterIndex,
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
                : Theme.of(context).colorScheme.surfaceContainerHighest,
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
              ? Icon(Icons.check_circle_rounded,
                  size: 18, color: Theme.of(context).colorScheme.primary)
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
    required this.paragraphKeys,
    required this.onToggleImmersive,
    required this.onParagraphKeys,
    required this.onWordOffsets,
    required this.onNavigateChapter,
    this.isEstimatingProgress = false,
  });

  final ReaderState state;
  final ReadingPreferences prefs;
  final ReadingPaletteColors colors;
  final bool immersive;
  final ScrollController? scrollController;
  final List<GlobalKey> paragraphKeys;
  final VoidCallback onToggleImmersive;
  final void Function(List<GlobalKey>) onParagraphKeys;
  final void Function(List<int>) onWordOffsets;
  final void Function(int) onNavigateChapter;
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
    _cachedChapterWordMax =
        chapter.words.isNotEmpty ? chapter.words.length : chapter.wordCount;

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

    return GestureDetector(
      onTap: widget.onToggleImmersive,
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
                final pct =
                    (s.progress * 100).clamp(0, 100).toStringAsFixed(1);
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
              onChanged: (v) => context
                  .read<ReaderBloc>()
                  .add(ReaderWordIndexChanged(v.round())),
            ),
            ),
          Expanded(
            child: Builder(builder: (context) {
              final textStyle = TextStyle(
                color: colors.foreground,
                fontSize: prefs.fontSize,
                height: prefs.lineHeight,
                letterSpacing: prefs.letterSpacing,
                fontFamily: prefs.fontFamilyName,
              );

        return Center(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: prefs.maxColumnWidth),
            child: ListView.builder(
              key: ValueKey(prefs.fontFamilyName),
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              itemCount: paragraphs.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  final chapter = widget.state.currentChapter;
                  return _EditorialChapterHeader(
                    chapterNumber: widget.state.currentChapterIndex + 1,
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
            }),
          ),
          if (!widget.immersive)
            _ChapterNavBar(
              canPrev: state.currentChapterIndex > 0,
              canNext:
                  state.currentChapterIndex < state.chapters.length - 1,
              foreground: colors.foreground,
              background: scheme.surfaceContainerHighest,
              onPrev: () => widget.onNavigateChapter(-1),
              onNext: () => widget.onNavigateChapter(1),
            ),
        ],
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

class _PositionSlider extends StatelessWidget {
  const _PositionSlider({
    required this.currentWord,
    required this.maxWords,
    required this.ttsStatus,
    required this.foreground,
    required this.accent,
    required this.onChanged,
    this.isEstimatingProgress = false,
  });

  final int currentWord;
  final int maxWords;
  final TtsPlaybackStatus ttsStatus;
  final Color foreground;
  final Color accent;
  final ValueChanged<double> onChanged;
  final bool isEstimatingProgress;

  @override
  Widget build(BuildContext context) {
    final indicator = switch (ttsStatus) {
      TtsPlaybackStatus.loading => const SizedBox(
          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      TtsPlaybackStatus.playing =>
        Icon(Icons.graphic_eq_rounded, size: 16, color: accent),
      TtsPlaybackStatus.error =>
        const Icon(Icons.volume_off_rounded, size: 16, color: Colors.red),
      _ => const SizedBox.shrink(),
    };

    final estimateBadge = isEstimatingProgress &&
            (ttsStatus == TtsPlaybackStatus.playing ||
                ttsStatus == TtsPlaybackStatus.loading)
        ? Tooltip(
            message: 'Sincronización aproximada',
            child: Icon(
              Icons.bolt_rounded,
              size: 14,
              color: foreground.withValues(alpha: 0.5),
            ),
          )
        : const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$currentWord / $maxWords palabras',
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              estimateBadge,
              const SizedBox(width: 4),
              indicator,
              _ReadingTimer(color: foreground.withValues(alpha: 0.7)),
            ],
          ),
          Semantics(
            label: 'Posición de lectura: $currentWord de $maxWords palabras',
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: accent,
                inactiveTrackColor: foreground.withValues(alpha: 0.15),
                thumbColor: accent,
                overlayColor: accent.withValues(alpha: 0.1),
                trackHeight: 3,
              ),
              child: Slider(
                value: currentWord.toDouble().clamp(0, maxWords.toDouble()),
                min: 0,
                max: maxWords.toDouble(),
                onChanged: onChanged,
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
    required this.paragraph,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.textStyle,
    this.accentColor,
    this.isFirstParagraph = false,
    super.key,
  });

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
      final wordCount =
          part.split(_wsRegex).where((w) => w.isNotEmpty).length;
      if (wordCount == 0) continue;
      sentences.add(_Sentence(
        text: part,
        wordStart: wordCursor,
        wordEnd: wordCursor + wordCount - 1,
      ));
      wordCursor += wordCount;
    }
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
      child: BlocBuilder<ReaderBloc, ReaderState>(
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
          final highlight = (widget.accentColor ??
                  Theme.of(context).colorScheme.primaryContainer)
              .withValues(alpha: 0.12);

          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _sentences.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(
                        vertical: 2, horizontal: 6),
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
            top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
  String _externalVoiceId = '21m00Tcm4TlvDq8ikWAW';
  TtsCapabilities _caps = kIsWeb ? TtsCapabilities.web : TtsCapabilities.mobile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mode = await getTtsMode();
    final externalId = await getSelectedVoiceId();
    final selected = await getNativeVoice();
    final all = _caps.supportsVoiceSelection
        ? await sl<DeviceTtsRepository>().getAvailableVoices()
        : const <Map<String, String>>[];
    // Prefer es-* and en-* voices, sorted by locale.
    final filtered = all.where((v) {
      final loc = (v['locale'] ?? '').toLowerCase();
      return loc.startsWith('es') || loc.startsWith('en');
    }).toList()
      ..sort((a, b) =>
          (a['locale'] ?? '').compareTo(b['locale'] ?? ''));
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _externalVoiceId = externalId;
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

  Future<void> _selectExternal(_Voice voice) async {
    final bloc = context.read<ReaderBloc>();
    final wasActive = bloc.state.isTtsActive;
    Navigator.pop(context);
    await setTtsMode(TtsMode.external);
    await setSelectedVoiceId(voice.id);
    if (sl.isRegistered<TtsRepositoryProxy>()) {
      await sl<TtsRepositoryProxy>()
          .switchMode(TtsMode.external, voiceId: voice.id);
    }
    if (wasActive) bloc.add(const ReaderTtsRestart());
  }

  String _voiceSubtitle(Map<String, String> v) {
    final locale = v['locale'] ?? '';
    final gender = v['gender'];
    final neural = _isNeuralVoice(v) ? 'Neural' : '';
    final parts = [locale, gender, neural].where((p) => p != null && p.isNotEmpty);
    return parts.join(' · ');
  }

  bool _isNativeSelected(Map<String, String> v) {
    final s = _selectedNative;
    if (s == null) return false;
    return s['name'] == v['name'] && s['locale'] == v['locale'];
  }

  bool _isNeuralVoice(Map<String, String> v) {
    final name = (v['name'] ?? '').toLowerCase();
    return name.contains('natural') || name.contains('neural') ||
        name.contains('wavenet') || name.contains('neural2');
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
                  child: Text('Voz para audio',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
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
                    padding:
                        EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      'La selección de voz no está disponible en esta plataforma.',
                      style: TextStyle(fontSize: 13),
                    ),
                  )
                else if (_nativeVoices.isEmpty)
                  const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text(
                    'Voces en la nube (ElevenLabs)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final voice in _elevenVoices)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.cloud_outlined,
                      color: _mode == TtsMode.external &&
                              _externalVoiceId == voice.id
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(voice.name),
                    subtitle: Text(voice.description),
                    trailing: _mode == TtsMode.external &&
                            _externalVoiceId == voice.id
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => _selectExternal(voice),
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
                child: Text('Velocidad de lectura',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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

// ── Voice catalog ──

class _Voice {
  const _Voice(this.id, this.name, this.description);
  final String id;
  final String name;
  final String description;
}

const _elevenVoices = [
  _Voice('IT3qq4f9SOwYMAmpJ9pW', 'Español MX', 'Voz femenina mexicana'),
  _Voice('FGlbemCpQBuN6Wl0xb0m', 'Español ES', 'Voz masculina española'),
  _Voice('j5KPlErZBIQsqRqS4S3S', 'Español US', 'Voz neutra latina'),
  _Voice('21m00Tcm4TlvDq8ikWAW', 'Rachel', 'Voz femenina cálida (EN)'),
  _Voice('ErXwobaYiN019PkySvjV', 'Antoni', 'Voz masculina profunda (EN)'),
];
