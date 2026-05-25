import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/highlight.dart';

/// Persists per-book highlights in SharedPreferences. Keyed by book ID
/// so opening a book loads only its highlights and saves stay scoped.
class HighlightRepository {
  static const _keyPrefix = 'highlights_';

  final StreamController<String> _changesController =
      StreamController<String>.broadcast();

  /// Fires the bookId whenever its highlight list changes (add /
  /// remove / colour edit). UI components watching a book can refresh
  /// without polling.
  Stream<String> get changes => _changesController.stream;

  void dispose() {
    _changesController.close();
  }

  Future<List<Highlight>> getHighlights(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyPrefix$bookId');
    if (raw == null || raw.isEmpty) return <Highlight>[];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Highlight.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[HighlightRepo] parse error: $e');
      return <Highlight>[];
    }
  }

  Future<List<Highlight>> getHighlightsForChapter(
    String bookId,
    String chapterId,
  ) async {
    final all = await getHighlights(bookId);
    return all.where((h) => h.chapterId == chapterId).toList();
  }

  Future<void> addHighlight(Highlight highlight) async {
    final list = await getHighlights(highlight.bookId);
    // Skip duplicates of the same range in the same chapter.
    final existing = list.any((h) =>
        h.chapterId == highlight.chapterId &&
        h.startWordIndex == highlight.startWordIndex &&
        h.endWordIndex == highlight.endWordIndex);
    if (existing) return;
    list.add(highlight);
    await _save(highlight.bookId, list);
  }

  Future<void> updateHighlight(Highlight highlight) async {
    final list = await getHighlights(highlight.bookId);
    final idx = list.indexWhere((h) => h.id == highlight.id);
    if (idx >= 0) {
      list[idx] = highlight;
      await _save(highlight.bookId, list);
    }
  }

  Future<void> removeHighlight(String bookId, String id) async {
    final list = await getHighlights(bookId);
    list.removeWhere((h) => h.id == id);
    await _save(bookId, list);
  }

  Future<void> _save(String bookId, List<Highlight> list) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(list.map((h) => h.toJson()).toList());
    await prefs.setString('$_keyPrefix$bookId', json);
    if (!_changesController.isClosed) _changesController.add(bookId);
  }
}
