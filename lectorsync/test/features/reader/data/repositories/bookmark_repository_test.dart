import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/bookmark_repository.dart';
import 'package:lectorsync/features/reader/domain/entities/bookmark.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('BookmarkRepository CRUD', () {
    test('returns empty list for new book', () async {
      final repo = BookmarkRepository();
      final bookmarks = await repo.getBookmarks('book-1');
      expect(bookmarks, isEmpty);
    });

    test('addBookmark persists and is returned by getBookmarks', () async {
      final repo = BookmarkRepository();
      final bm = Bookmark(
        id: 'bm-1',
        bookId: 'book-1',
        chapterId: 'ch-1',
        chapterTitle: 'Chapter One',
        wordIndex: 42,
        snippet: 'snippet text',
        createdAt: DateTime(2026, 5, 19, 10, 30),
      );

      await repo.addBookmark(bm);
      final list = await repo.getBookmarks('book-1');

      expect(list.length, 1);
      expect(list.first.id, 'bm-1');
      expect(list.first.wordIndex, 42);
      expect(list.first.snippet, 'snippet text');
    });

    test('duplicate position is silently ignored', () async {
      final repo = BookmarkRepository();
      final bm1 = Bookmark(
        id: 'bm-1',
        bookId: 'book-1',
        chapterId: 'ch-1',
        chapterTitle: '',
        wordIndex: 10,
        snippet: '',
        createdAt: DateTime.now(),
      );
      final bm2Same = Bookmark(
        id: 'bm-2',
        bookId: 'book-1',
        chapterId: 'ch-1',
        chapterTitle: '',
        wordIndex: 10, // same chapter + word as bm1
        snippet: '',
        createdAt: DateTime.now(),
      );

      await repo.addBookmark(bm1);
      await repo.addBookmark(bm2Same);

      final list = await repo.getBookmarks('book-1');
      expect(list.length, 1);
      expect(list.first.id, 'bm-1');
    });

    test('removeBookmark removes by id', () async {
      final repo = BookmarkRepository();
      final bm = Bookmark(
        id: 'to-remove',
        bookId: 'book-1',
        chapterId: 'ch-1',
        chapterTitle: '',
        wordIndex: 5,
        snippet: '',
        createdAt: DateTime.now(),
      );

      await repo.addBookmark(bm);
      expect((await repo.getBookmarks('book-1')).length, 1);

      await repo.removeBookmark('book-1', 'to-remove');
      expect((await repo.getBookmarks('book-1')).length, 0);
    });

    test('updateBookmark updates note', () async {
      final repo = BookmarkRepository();
      final bm = Bookmark(
        id: 'bm-1',
        bookId: 'book-1',
        chapterId: 'ch-1',
        chapterTitle: '',
        wordIndex: 1,
        snippet: '',
        createdAt: DateTime.now(),
      );

      await repo.addBookmark(bm);
      await repo.updateBookmark(bm.copyWith(note: 'My note'));

      final list = await repo.getBookmarks('book-1');
      expect(list.first.note, 'My note');
    });

    test('isBookmarked returns true for existing position', () async {
      final repo = BookmarkRepository();
      final bm = Bookmark(
        id: 'bm-1',
        bookId: 'book-1',
        chapterId: 'ch-1',
        chapterTitle: '',
        wordIndex: 25,
        snippet: '',
        createdAt: DateTime.now(),
      );
      await repo.addBookmark(bm);

      expect(await repo.isBookmarked('book-1', 'ch-1', 25), isTrue);
      expect(await repo.isBookmarked('book-1', 'ch-1', 26), isFalse);
    });

    test('bookmarks are sorted newest-first', () async {
      final repo = BookmarkRepository();
      final older = Bookmark(
        id: 'older',
        bookId: 'book-1',
        chapterId: 'ch-1',
        chapterTitle: '',
        wordIndex: 1,
        snippet: '',
        createdAt: DateTime(2026, 1, 1),
      );
      final newer = Bookmark(
        id: 'newer',
        bookId: 'book-1',
        chapterId: 'ch-1',
        chapterTitle: '',
        wordIndex: 2,
        snippet: '',
        createdAt: DateTime(2026, 5, 1),
      );

      await repo.addBookmark(older);
      await repo.addBookmark(newer);

      final list = await repo.getBookmarks('book-1');
      expect(list.first.id, 'newer');
      expect(list.last.id, 'older');
    });

    test('changes stream fires on add', () async {
      final repo = BookmarkRepository();
      final emitted = <String>[];
      final sub = repo.changes.listen(emitted.add);

      await repo.addBookmark(Bookmark(
        id: 'bm-1',
        bookId: 'book-x',
        chapterId: 'ch-1',
        chapterTitle: '',
        wordIndex: 0,
        snippet: '',
        createdAt: DateTime.now(),
      ));

      // Give the stream microtask a chance to flush.
      await Future<void>.delayed(Duration.zero);

      expect(emitted, contains('book-x'));
      await sub.cancel();
      repo.dispose();
    });
  });
}
