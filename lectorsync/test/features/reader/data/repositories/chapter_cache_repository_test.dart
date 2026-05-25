import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/chapter_cache_repository.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('ChapterCacheRepository', () {
    test('returns null for uncached chapter', () async {
      final repo = ChapterCacheRepository();
      final chapter = await repo.getCachedChapter('ch-missing');
      expect(chapter, isNull);
    });

    test('cacheChapter stores and getCachedChapter retrieves', () async {
      final repo = ChapterCacheRepository();
      final chapter = const Chapter(
        id: 'ch-1',
        title: 'First Chapter',
        orderIndex: 0,
        wordCount: 3,
        text: 'hello world today',
        words: ['hello', 'world', 'today'],
      );

      await repo.cacheChapter('book-1', chapter);
      final retrieved = await repo.getCachedChapter('ch-1');

      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'ch-1');
      expect(retrieved.title, 'First Chapter');
      expect(retrieved.text, 'hello world today');
      expect(retrieved.words, ['hello', 'world', 'today']);
    });

    test('cacheChapter ignores chapters with empty text', () async {
      final repo = ChapterCacheRepository();
      final empty = const Chapter(
        id: 'ch-empty',
        title: '',
        orderIndex: 0,
        wordCount: 0,
        text: '',
        words: [],
      );

      await repo.cacheChapter('book-1', empty);
      expect(await repo.isCached('ch-empty'), isFalse);
    });

    test('isCached returns true after caching', () async {
      final repo = ChapterCacheRepository();
      final chapter = const Chapter(
        id: 'ch-2',
        title: '',
        orderIndex: 0,
        wordCount: 1,
        text: 'word',
        words: ['word'],
      );

      expect(await repo.isCached('ch-2'), isFalse);
      await repo.cacheChapter('book-1', chapter);
      expect(await repo.isCached('ch-2'), isTrue);
    });

    test('getCachedIds tracks cached chapters per book', () async {
      final repo = ChapterCacheRepository();
      await repo.cacheChapter(
        'book-A',
        const Chapter(
          id: 'a-1',
          title: '',
          orderIndex: 0,
          wordCount: 1,
          text: 'x',
          words: ['x'],
        ),
      );
      await repo.cacheChapter(
        'book-A',
        const Chapter(
          id: 'a-2',
          title: '',
          orderIndex: 1,
          wordCount: 1,
          text: 'y',
          words: ['y'],
        ),
      );

      final ids = await repo.getCachedIds('book-A');
      expect(ids, containsAll(['a-1', 'a-2']));
    });

    test('clearBookCache removes only that book', () async {
      final repo = ChapterCacheRepository();
      await repo.cacheChapter(
        'book-keep',
        const Chapter(
          id: 'k-1',
          title: '',
          orderIndex: 0,
          wordCount: 1,
          text: 'k',
          words: ['k'],
        ),
      );
      await repo.cacheChapter(
        'book-drop',
        const Chapter(
          id: 'd-1',
          title: '',
          orderIndex: 0,
          wordCount: 1,
          text: 'd',
          words: ['d'],
        ),
      );

      await repo.clearBookCache('book-drop');

      expect(await repo.isCached('k-1'), isTrue);
      expect(await repo.isCached('d-1'), isFalse);
    });

    test('getCacheInfo reports counts and approximate bytes', () async {
      final repo = ChapterCacheRepository();
      await repo.cacheChapter(
        'book-1',
        const Chapter(
          id: 'ch-1',
          title: 't',
          orderIndex: 0,
          wordCount: 2,
          text: 'hello world',
          words: ['hello', 'world'],
        ),
      );

      final info = await repo.getCacheInfo('book-1');
      expect(info.chapters, 1);
      expect(info.estimatedBytes, greaterThan(0));
    });
  });
}
