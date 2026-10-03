import 'package:flutter/material.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../data/repositories/book_shelf_repository.dart';

/// Sheet for assigning / removing a book from named shelves.
///
/// Users can:
///   - Toggle shelf membership via filter chips.
///   - Create a new shelf via the "+" action at the top.
///   - Delete custom shelves (the 3 defaults can be emptied but not
///     removed entirely).
class BookShelvesSheet extends StatefulWidget {
  const BookShelvesSheet({
    super.key,
    required this.bookId,
    required this.bookTitle,
  });

  final String bookId;
  final String bookTitle;

  @override
  State<BookShelvesSheet> createState() => _BookShelvesSheetState();
}

class _BookShelvesSheetState extends State<BookShelvesSheet> {
  Map<String, List<String>> _all = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await sl<BookShelfRepository>().getAll();
    if (mounted) {
      setState(() {
        _all = all;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(String shelf) async {
    await sl<BookShelfRepository>()
        .toggleBookInShelf(shelf, widget.bookId);
    await _load();
  }

  Future<void> _createShelf() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva estantería'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await sl<BookShelfRepository>().createShelf(name);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Material(
        color: Theme.of(context).bottomSheetTheme.backgroundColor ??
            scheme.surface,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : screenWidth;
                  return SizedBox(
                    width: w,
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Icon(Icons.collections_bookmark_rounded,
                              color: scheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Estanterías',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  widget.bookTitle,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _createShelf,
                            tooltip: 'Nueva estantería',
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const LoadingView(message: 'Cargando tus estanterías')
                    : SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(20),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _all.keys.map((shelf) {
                            final selected =
                                _all[shelf]?.contains(widget.bookId) ??
                                    false;
                            return FilterChip(
                              label: Text(shelf),
                              selected: selected,
                              onSelected: (_) => _toggle(shelf),
                              avatar: selected
                                  ? Icon(Icons.check_rounded,
                                      size: 16,
                                      color: scheme.onPrimary)
                                  : null,
                            );
                          }).toList(),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
