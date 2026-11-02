import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../data/repositories/bookmark_repository.dart';
import '../../domain/entities/bookmark.dart';

class BookmarksSheet extends StatefulWidget {
  const BookmarksSheet({
    super.key,
    required this.bookId,
    required this.onNavigate,
    this.onAddCurrent,
    this.canAddCurrent = false,
  });

  final String bookId;
  final void Function(String chapterId, int wordIndex) onNavigate;
  final VoidCallback? onAddCurrent;
  final bool canAddCurrent;

  @override
  State<BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<BookmarksSheet> {
  List<Bookmark> _bookmarks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = sl<BookmarkRepository>();
    final bookmarks = await repo.getBookmarks(widget.bookId);
    if (mounted) {
      setState(() {
        _bookmarks = bookmarks;
        _loading = false;
      });
    }
  }

  Future<void> _delete(Bookmark bookmark) async {
    final repo = sl<BookmarkRepository>();
    await repo.removeBookmark(widget.bookId, bookmark.id);
    await _load();
  }

  String _buildJsonExport() {
    final exportData = {
      'exportedAt': DateTime.now().toIso8601String(),
      'bookId': widget.bookId,
      'count': _bookmarks.length,
      'bookmarks': _bookmarks.map((b) => b.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  /// Human-readable Markdown export, much easier to paste into a notes
  /// app (Obsidian, Notion, Bear) than raw JSON. Each bookmark gets a
  /// `##` header with chapter title + date, then italic snippet, then
  /// optional note as a blockquote.
  String _buildMarkdownExport() {
    final buf = StringBuffer()
      ..writeln('# Marcadores')
      ..writeln()
      ..writeln('_Exportado ${DateTime.now().toIso8601String()}_')
      ..writeln()
      ..writeln('Total: ${_bookmarks.length} marcador'
          '${_bookmarks.length == 1 ? '' : 'es'}')
      ..writeln();
    for (final bm in _bookmarks) {
      final d = bm.createdAt;
      final dateStr = '${d.day}/${d.month}/${d.year} '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
      buf
        ..writeln('## ${bm.chapterTitle.isNotEmpty ? bm.chapterTitle : 'Capítulo'}')
        ..writeln()
        ..writeln('_$dateStr · palabra ${bm.wordIndex}_')
        ..writeln();
      if (bm.snippet.isNotEmpty) {
        buf
          ..writeln('> "${bm.snippet}"')
          ..writeln();
      }
      if (bm.note != null && bm.note!.isNotEmpty) {
        buf
          ..writeln('**Nota:** ${bm.note}')
          ..writeln();
      }
      buf.writeln('---');
      buf.writeln();
    }
    return buf.toString();
  }

  Future<void> _export(String format) async {
    if (_bookmarks.isEmpty) return;

    final isMarkdown = format == 'md';
    final content = isMarkdown ? _buildMarkdownExport() : _buildJsonExport();
    final extension = isMarkdown ? 'md' : 'json';
    final messenger = ScaffoldMessenger.of(context);

    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Exportar marcadores',
        fileName:
            'bookmarks-${DateTime.now().millisecondsSinceEpoch}.$extension',
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: utf8.encode(content),
      );
      if (path != null && !kIsWeb) {
        messenger.showSnackBar(SnackBar(
          content: Text('Exportado: $path'),
          duration: const Duration(seconds: 3),
        ));
        return;
      }
      if (kIsWeb) {
        messenger.showSnackBar(SnackBar(
          content: Text('Descarga ${isMarkdown ? "Markdown" : "JSON"} iniciada'),
          duration: const Duration(seconds: 2),
        ));
        return;
      }
    } catch (e) {
      debugPrint('[BookmarksSheet] export saveFile failed: $e');
    }

    // Fallback: clipboard.
    await Clipboard.setData(ClipboardData(text: content));
    messenger.showSnackBar(SnackBar(
      content: Text('Marcadores (${isMarkdown ? "MD" : "JSON"}) '
          'copiados al portapapeles'),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _editNote(Bookmark bookmark) async {
    final controller = TextEditingController(text: bookmark.note ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar nota'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Escribe tu nota aquí...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result != null) {
      final repo = sl<BookmarkRepository>();
      await repo.updateBookmark(bookmark.copyWith(note: result));
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
      // SafeArea + Material at the top provides bounded constraints
      // even if the modal route hands us unbounded width during the
      // entrance animation. Without this, any Row with Expanded or
      // Spacer below would crash with _debugRelayoutBoundary +
      // RenderBox not laid out assertions on first open.
      builder: (context, scrollController) => Material(
        color: Theme.of(context).bottomSheetTheme.backgroundColor ??
            Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              // LayoutBuilder pins explicit bounded width on the header
              // Row so its children (including Material buttons whose
              // _InputPadding expects a bounded width) never receive
              // `w=Infinity` constraints.
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : screenWidth;
                  return SizedBox(
                    width: w,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Icon(Icons.bookmark_rounded,
                              color: scheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Marcadores (${_bookmarks.length})',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_bookmarks.isNotEmpty)
                            PopupMenuButton<String>(
                              tooltip: 'Exportar marcadores',
                              icon: const Icon(
                                Icons.ios_share_rounded,
                                size: 20,
                              ),
                              onSelected: _export,
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'md',
                                  child: ListTile(
                                    leading: Icon(Icons.notes_rounded),
                                    title: Text('Markdown (.md)'),
                                    subtitle: Text('Para notas / Obsidian'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'json',
                                  child: ListTile(
                                    leading: Icon(Icons.code_rounded),
                                    title: Text('JSON (.json)'),
                                    subtitle: Text('Para reimportar'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                          if (widget.canAddCurrent &&
                              widget.onAddCurrent != null)
                            TextButton.icon(
                              onPressed: () async {
                                widget.onAddCurrent!.call();
                                await Future.delayed(
                                    const Duration(milliseconds: 200));
                                await _load();
                              },
                              icon: const Icon(Icons.add_rounded,
                                  size: 18),
                              label: const Text('Aquí'),
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.primary,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                visualDensity: VisualDensity.compact,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
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
                ? const LoadingView(message: 'Cargando tus marcadores')
                : _bookmarks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bookmark_border_rounded, size: 48,
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text(
                              'No hay marcadores aún',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Mantén presionado un párrafo para agregar uno',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _bookmarks.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                        itemBuilder: (context, index) {
                          final bm = _bookmarks[index];
                          final d = bm.createdAt;
                          final dateStr = '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: scheme.primaryContainer,
                              child: Icon(Icons.bookmark_rounded, size: 18,
                                  color: scheme.onPrimaryContainer),
                            ),
                            title: Text(
                              bm.chapterTitle.isNotEmpty ? bm.chapterTitle : 'Capítulo',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (bm.snippet.isNotEmpty)
                                  Text(
                                    '"${bm.snippet}"',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (bm.note != null && bm.note!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      bm.note!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.primary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                Text(
                                  dateStr,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'note') _editNote(bm);
                                if (action == 'delete') _delete(bm);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'note',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_note_rounded, size: 18),
                                      SizedBox(width: 8),
                                      Text('Editar nota'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline_rounded, size: 18),
                                      SizedBox(width: 8),
                                      Text('Eliminar'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              widget.onNavigate(bm.chapterId, bm.wordIndex);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
