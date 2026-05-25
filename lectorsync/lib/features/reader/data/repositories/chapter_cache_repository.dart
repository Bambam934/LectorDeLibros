import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/chapter.dart';

/// Local chapter text cache for offline reading.
///
/// Caches chapter text in SharedPreferences under keys like
/// `chapter_cache_<chapterId>`. When the network is unavailable,
/// the reader can serve from this cache.
class ChapterCacheRepository {
  static const _cachePrefix = 'chapter_cache_';
  static const _cachedIdsPrefix = 'cached_chapter_ids_';

  /// Cache a chapter's full text.
  Future<void> cacheChapter(String bookId, Chapter chapter) async {
    if (chapter.text == null || chapter.text!.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode({
      'id': chapter.id,
      'title': chapter.title,
      'orderIndex': chapter.orderIndex,
      'wordCount': chapter.wordCount,
      'text': chapter.text,
      'cachedAt': DateTime.now().toIso8601String(),
    });
    await prefs.setString('$_cachePrefix${chapter.id}', data);

    // Track cached IDs per book.
    final idsKey = '$_cachedIdsPrefix$bookId';
    final ids = prefs.getStringList(idsKey) ?? [];
    if (!ids.contains(chapter.id)) {
      ids.add(chapter.id);
      await prefs.setStringList(idsKey, ids);
    }

    debugPrint('[ChapterCache] cached ${chapter.id} '
        '(${chapter.text!.length} chars)');
  }

  /// Retrieve a cached chapter, or null if not cached.
  Future<Chapter?> getCachedChapter(String chapterId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cachePrefix$chapterId');
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final text = json['text'] as String? ?? '';
      return Chapter(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? '',
        orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
        wordCount: (json['wordCount'] as num?)?.toInt() ?? 0,
        text: text,
        words: text
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList(growable: false),
      );
    } catch (e) {
      debugPrint('[ChapterCache] parse error for $chapterId: $e');
      return null;
    }
  }

  /// Check if a chapter is cached.
  Future<bool> isCached(String chapterId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_cachePrefix$chapterId');
  }

  /// Get all cached chapter IDs for a book.
  Future<List<String>> getCachedIds(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('$_cachedIdsPrefix$bookId') ?? [];
  }

  /// Get cache size info.
  Future<({int chapters, int estimatedBytes})> getCacheInfo(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('$_cachedIdsPrefix$bookId') ?? [];
    var totalBytes = 0;
    for (final id in ids) {
      final raw = prefs.getString('$_cachePrefix$id');
      if (raw != null) totalBytes += raw.length * 2; // Rough UTF-16 estimate.
    }
    return (chapters: ids.length, estimatedBytes: totalBytes);
  }

  /// Clear cache for a specific book.
  Future<void> clearBookCache(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('$_cachedIdsPrefix$bookId') ?? [];
    for (final id in ids) {
      await prefs.remove('$_cachePrefix$id');
    }
    await prefs.remove('$_cachedIdsPrefix$bookId');
    debugPrint('[ChapterCache] cleared ${ids.length} chapters for $bookId');
  }

  /// Clear all cached data.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(
      (k) => k.startsWith(_cachePrefix) || k.startsWith(_cachedIdsPrefix),
    );
    for (final key in keys) {
      await prefs.remove(key);
    }
    debugPrint('[ChapterCache] cleared all cache');
  }
}
