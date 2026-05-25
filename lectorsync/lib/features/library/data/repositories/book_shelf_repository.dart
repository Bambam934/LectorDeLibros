import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local shelf / collection system. Each shelf is a named bucket that
/// references a set of book IDs. Three default shelves are always
/// present (Leyendo, Por leer, Favoritos) but users can add custom
/// ones via the library UI.
///
/// Server-side sync is intentionally out of scope for this iteration —
/// shelves live in SharedPreferences only.
class BookShelfRepository {
  static const _shelvesKey = 'book_shelves_v1';

  static const defaultShelves = <String>[
    'Leyendo',
    'Por leer',
    'Favoritos',
  ];

  final StreamController<void> _changesController =
      StreamController<void>.broadcast();

  Stream<void> get changes => _changesController.stream;

  void dispose() {
    _changesController.close();
  }

  /// Returns the entire shelves map: shelf-name → list of book IDs.
  Future<Map<String, List<String>>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_shelvesKey);
    final result = <String, List<String>>{};
    // Seed defaults so the UI always has at least these chips.
    for (final s in defaultShelves) {
      result[s] = <String>[];
    }
    if (raw == null || raw.isEmpty) return result;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in map.entries) {
        result[entry.key] =
            (entry.value as List).map((e) => e.toString()).toList();
      }
    } catch (e) {
      debugPrint('[ShelfRepo] parse error: $e');
    }
    return result;
  }

  Future<List<String>> getShelfNames() async {
    final all = await getAll();
    return all.keys.toList();
  }

  /// Get the set of shelves a given book belongs to.
  Future<List<String>> getShelvesForBook(String bookId) async {
    final all = await getAll();
    return all.entries
        .where((e) => e.value.contains(bookId))
        .map((e) => e.key)
        .toList();
  }

  Future<List<String>> getBooksInShelf(String shelfName) async {
    final all = await getAll();
    return all[shelfName] ?? <String>[];
  }

  Future<void> addBookToShelf(String shelfName, String bookId) async {
    final all = await getAll();
    final shelf = all[shelfName] ?? <String>[];
    if (!shelf.contains(bookId)) {
      shelf.add(bookId);
      all[shelfName] = shelf;
      await _save(all);
    }
  }

  Future<void> removeBookFromShelf(String shelfName, String bookId) async {
    final all = await getAll();
    final shelf = all[shelfName];
    if (shelf == null) return;
    shelf.remove(bookId);
    all[shelfName] = shelf;
    await _save(all);
  }

  /// Toggle membership — convenient for chip-style UI.
  Future<bool> toggleBookInShelf(String shelfName, String bookId) async {
    final all = await getAll();
    final shelf = all[shelfName] ?? <String>[];
    final wasIn = shelf.contains(bookId);
    if (wasIn) {
      shelf.remove(bookId);
    } else {
      shelf.add(bookId);
    }
    all[shelfName] = shelf;
    await _save(all);
    return !wasIn; // new membership state
  }

  Future<void> createShelf(String name) async {
    if (name.trim().isEmpty) return;
    final all = await getAll();
    if (all.containsKey(name)) return;
    all[name] = <String>[];
    await _save(all);
  }

  Future<void> deleteShelf(String name) async {
    if (defaultShelves.contains(name)) {
      // Don't delete defaults — clear contents instead.
      final all = await getAll();
      all[name] = <String>[];
      await _save(all);
      return;
    }
    final all = await getAll();
    all.remove(name);
    await _save(all);
  }

  Future<void> _save(Map<String, List<String>> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shelvesKey, jsonEncode(data));
    if (!_changesController.isClosed) _changesController.add(null);
  }
}
