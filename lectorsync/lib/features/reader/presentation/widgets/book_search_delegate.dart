import 'package:flutter/material.dart';

import '../../domain/entities/chapter.dart';
import '../../domain/repositories/reader_repository.dart';

/// Result of an in-book search hit.
class SearchResult {
  const SearchResult({
    required this.chapterId,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.snippet,
    required this.wordIndex,
  });

  final String chapterId;
  final String chapterTitle;
  final int chapterIndex;
  final String snippet;
  final int wordIndex;
}

/// SearchDelegate that searches across all chapters of the current book.
class BookSearchDelegate extends SearchDelegate<SearchResult?> {
  BookSearchDelegate({
    required this.chapters,
    required this.readerRepository,
    required this.bookId,
    required this.currentChapter,
  }) : super(
          searchFieldLabel: 'Buscar en el libro...',
          searchFieldStyle: const TextStyle(fontSize: 16),
        );

  final List<Chapter> chapters;
  final ReaderRepository readerRepository;
  final String bookId;
  final Chapter? currentChapter;

  // Cache loaded chapter texts.
  final Map<String, String> _chapterTexts = {};

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear_rounded),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _SearchResultsView(
      query: query,
      chapters: chapters,
      readerRepository: readerRepository,
      bookId: bookId,
      currentChapter: currentChapter,
      chapterTexts: _chapterTexts,
      onResultTap: (result) => close(context, result),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.length < 2) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'Escribe al menos 2 caracteres para buscar',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    return buildResults(context);
  }
}

class _SearchResultsView extends StatefulWidget {
  const _SearchResultsView({
    required this.query,
    required this.chapters,
    required this.readerRepository,
    required this.bookId,
    required this.currentChapter,
    required this.chapterTexts,
    required this.onResultTap,
  });

  final String query;
  final List<Chapter> chapters;
  final ReaderRepository readerRepository;
  final String bookId;
  final Chapter? currentChapter;
  final Map<String, String> chapterTexts;
  final void Function(SearchResult) onResultTap;

  @override
  State<_SearchResultsView> createState() => _SearchResultsViewState();
}

class _SearchResultsViewState extends State<_SearchResultsView> {
  List<SearchResult> _results = [];
  bool _searching = true;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(covariant _SearchResultsView old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _search();
  }

  Future<void> _search() async {
    if (widget.query.length < 2) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    if (widget.query == _lastQuery) return;
    _lastQuery = widget.query;

    setState(() => _searching = true);

    final results = <SearchResult>[];
    final queryLower = widget.query.toLowerCase();

    // Search in current chapter first (already loaded).
    final current = widget.currentChapter;
    if (current != null && current.text != null) {
      widget.chapterTexts[current.id] = current.text!;
      _addResultsFromText(
        results,
        current.id,
        current.title,
        widget.chapters.indexWhere((c) => c.id == current.id),
        current.text!,
        queryLower,
      );
    }

    // Search in other chapters — load text if needed.
    for (var i = 0; i < widget.chapters.length; i++) {
      final ch = widget.chapters[i];
      if (ch.id == current?.id) continue;

      String? text = widget.chapterTexts[ch.id];
      if (text == null) {
        // Load chapter text from API.
        final result = await widget.readerRepository.getChapter(
          bookId: widget.bookId,
          chapterId: ch.id,
        );
        result.fold(
          (_) {},
          (loaded) {
            text = loaded.text ?? '';
            widget.chapterTexts[ch.id] = text!;
          },
        );
      }
      if (text != null && text!.isNotEmpty) {
        _addResultsFromText(results, ch.id, ch.title, i, text!, queryLower);
      }

      // Check if query changed during async load.
      if (widget.query != _lastQuery) return;
    }

    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  void _addResultsFromText(
    List<SearchResult> results,
    String chapterId,
    String chapterTitle,
    int chapterIndex,
    String text,
    String queryLower,
  ) {
    final textLower = text.toLowerCase();
    var pos = 0;
    while (true) {
      final idx = textLower.indexOf(queryLower, pos);
      if (idx == -1) break;

      // Build snippet: ~30 chars before and after.
      final snippetStart = (idx - 30).clamp(0, text.length);
      final snippetEnd = (idx + queryLower.length + 30).clamp(0, text.length);
      final snippet = '${snippetStart > 0 ? '…' : ''}'
          '${text.substring(snippetStart, snippetEnd)}'
          '${snippetEnd < text.length ? '…' : ''}';

      // Estimate word index.
      final beforeText = text.substring(0, idx);
      final wordIndex = beforeText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

      results.add(SearchResult(
        chapterId: chapterId,
        chapterTitle: chapterTitle,
        chapterIndex: chapterIndex,
        snippet: snippet,
        wordIndex: wordIndex,
      ));

      pos = idx + queryLower.length;
      // Limit results per chapter.
      if (results.length >= 50) break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 48,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'No se encontraron resultados para "${widget.query}"',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '${_results.length} resultado${_results.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final result = _results[index - 1];
        return _SearchResultTile(
          result: result,
          query: widget.query,
          onTap: () => widget.onResultTap(result),
        );
      },
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.result,
    required this.query,
    required this.onTap,
  });

  final SearchResult result;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: scheme.primaryContainer,
        child: Text(
          '${result.chapterIndex + 1}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Text(
        result.chapterTitle,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: _HighlightedSnippet(
        snippet: result.snippet,
        query: query,
      ),
      onTap: onTap,
    );
  }
}

class _HighlightedSnippet extends StatelessWidget {
  const _HighlightedSnippet({
    required this.snippet,
    required this.query,
  });

  final String snippet;
  final String query;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spans = <TextSpan>[];
    final lower = snippet.toLowerCase();
    final queryLower = query.toLowerCase();
    var pos = 0;

    while (pos < snippet.length) {
      final idx = lower.indexOf(queryLower, pos);
      if (idx == -1) {
        spans.add(TextSpan(text: snippet.substring(pos)));
        break;
      }
      if (idx > pos) {
        spans.add(TextSpan(text: snippet.substring(pos, idx)));
      }
      spans.add(TextSpan(
        text: snippet.substring(idx, idx + query.length),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          backgroundColor: scheme.primaryContainer.withValues(alpha: 0.5),
          color: scheme.primary,
        ),
      ));
      pos = idx + query.length;
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        children: spans,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
