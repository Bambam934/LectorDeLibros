import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/bookmark.dart';

/// Local bookmark repository backed by SharedPreferences.
///
/// Bookmarks are stored per-book as a JSON list under the key
/// `bookmarks_<bookId>`. This keeps storage lightweight and avoids
/// needing a full SQLite database for a simple feature.
class BookmarkRepository {
  static const _keyPrefix = 'bookmarks_';

  final StreamController<String> _changesController =
      StreamController<String>.broadcast();

  /// Stream of bookId values whenever bookmarks for that book change.
  /// UI components (count badges, lists) can subscribe to keep state
  /// consistent without polling.
  Stream<String> get changes => _changesController.stream;

  void dispose() {
    _changesController.close();
  }

  /// Get all bookmarks for a book, sorted newest-first.
  ///
  /// Returns a mutable list — callers (notably [addBookmark]) need to
  /// insert into the result, so a `const []` return would crash with
  /// "Cannot add to an unmodifiable list" for the first bookmark.
  Future<List<Bookmark>> getBookmarks(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyPrefix$bookId');
    if (raw == null || raw.isEmpty) return <Bookmark>[];

    try {
      final list = jsonDecode(raw) as List;
      final bookmarks = list
          .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return bookmarks;
    } catch (e) {
      debugPrint('[BookmarkRepo] parse error: $e');
      return <Bookmark>[];
    }
  }

  /// Add a new bookmark.
  Future<void> addBookmark(Bookmark bookmark) async {
    final bookmarks = await getBookmarks(bookmark.bookId);
    // Avoid duplicate at same position.
    final existing = bookmarks.where(
      (b) => b.chapterId == bookmark.chapterId && b.wordIndex == bookmark.wordIndex,
    );
    if (existing.isNotEmpty) return;

    bookmarks.insert(0, bookmark);
    await _save(bookmark.bookId, bookmarks);
  }

  /// Update an existing bookmark (e.g. edit note).
  Future<void> updateBookmark(Bookmark bookmark) async {
    final bookmarks = await getBookmarks(bookmark.bookId);
    final idx = bookmarks.indexWhere((b) => b.id == bookmark.id);
    if (idx >= 0) {
      bookmarks[idx] = bookmark;
      await _save(bookmark.bookId, bookmarks);
    }
  }

  /// Remove a bookmark by ID.
  Future<void> removeBookmark(String bookId, String bookmarkId) async {
    final bookmarks = await getBookmarks(bookId);
    bookmarks.removeWhere((b) => b.id == bookmarkId);
    await _save(bookId, bookmarks);
  }

  /// Check if a position is bookmarked.
  Future<bool> isBookmarked(String bookId, String chapterId, int wordIndex) async {
    final bookmarks = await getBookmarks(bookId);
    return bookmarks.any(
      (b) => b.chapterId == chapterId && b.wordIndex == wordIndex,
    );
  }

  Future<void> _save(String bookId, List<Bookmark> bookmarks) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(bookmarks.map((b) => b.toJson()).toList());
    await prefs.setString('$_keyPrefix$bookId', json);
    if (!_changesController.isClosed) {
      _changesController.add(bookId);
    }
  }
}
