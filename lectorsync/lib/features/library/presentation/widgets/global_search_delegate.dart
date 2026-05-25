import 'package:flutter/material.dart';

import '../../domain/entities/book.dart';

/// Result of a global library search hit.
class GlobalSearchResult {
  const GlobalSearchResult({
    required this.book,
    required this.matchType,
    this.snippet,
  });

  /// Source book this hit belongs to.
  final Book book;

  /// Where the match was found: `'title'`, `'author'`, or `'metadata'`.
  final String matchType;

  /// Optional excerpt (currently only used for title/author matches —
  /// full-text chapter search would require loading every chapter).
  final String? snippet;
}

/// Searches across the entire user library (titles + authors).
///
/// Full chapter-text search would require loading every chapter from
/// every book, which can be hundreds of MB. We keep this fast by
/// searching only metadata; per-book search is available from the
/// reader page itself.
class GlobalSearchDelegate extends SearchDelegate<GlobalSearchResult?> {
  GlobalSearchDelegate({
    required this.books,
  }) : super(
          searchFieldLabel: 'Buscar en mi biblioteca…',
          searchFieldStyle: const TextStyle(fontSize: 16),
        );

  final List<Book> books;

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

  List<GlobalSearchResult> _search(String q) {
    if (q.length < 2) return const [];
    final lower = q.toLowerCase();
    final results = <GlobalSearchResult>[];
    for (final book in books) {
      final titleMatch = book.title.toLowerCase().contains(lower);
      final authorMatch =
          book.author != null && book.author!.toLowerCase().contains(lower);
      if (titleMatch) {
        results.add(GlobalSearchResult(
          book: book,
          matchType: 'title',
          snippet: book.author,
        ));
      } else if (authorMatch) {
        results.add(GlobalSearchResult(
          book: book,
          matchType: 'author',
          snippet: book.title,
        ));
      }
    }
    return results;
  }

  @override
  Widget buildResults(BuildContext context) => _buildBody(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.length < 2) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.travel_explore_rounded,
                size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'Escribe al menos 2 caracteres para buscar\n'
              'en tu biblioteca (${books.length} libros)',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return _buildBody(context);
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = _search(query);

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'Sin resultados para "$query"',
              style:
                  TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: results.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              '${results.length} resultado${results.length == 1 ? '' : 's'} '
              'en ${books.length} libros',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final result = results[index - 1];
        return ListTile(
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: scheme.primaryContainer,
            child: Icon(
              result.matchType == 'title'
                  ? Icons.menu_book_rounded
                  : Icons.person_rounded,
              size: 20,
              color: scheme.onPrimaryContainer,
            ),
          ),
          title: _HighlightedText(
            text: result.book.title,
            query: query,
          ),
          subtitle: result.snippet != null
              ? Text(
                  result.snippet!,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: result.book.progress > 0 && result.book.progress < 1
              ? Text(
                  '${(result.book.progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                )
              : null,
          onTap: () => close(context, result),
        );
      },
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final spans = <TextSpan>[];
    var pos = 0;
    while (pos < text.length) {
      final idx = lower.indexOf(q, pos);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(pos)));
        break;
      }
      if (idx > pos) {
        spans.add(TextSpan(text: text.substring(pos, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
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
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black),
        children: spans.map((s) {
          return TextSpan(
            text: s.text,
            style: s.style ?? DefaultTextStyle.of(context).style,
          );
        }).toList(),
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
