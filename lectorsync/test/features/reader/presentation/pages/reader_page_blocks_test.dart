import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:lectorsync/core/di/injection_container.dart';
import 'package:lectorsync/core/errors/failures.dart';
import 'package:lectorsync/core/focus/focus_prefs.dart';
import 'package:lectorsync/core/focus/quiet_mode.dart';
import 'package:lectorsync/core/focus/system_fullscreen.dart';
import 'package:lectorsync/features/reader/data/repositories/bookmark_repository.dart';
import 'package:lectorsync/features/reader/data/repositories/device_tts_repository.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter_audio.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter_block.dart';
import 'package:lectorsync/features/reader/domain/repositories/reader_repository.dart';
import 'package:lectorsync/features/reader/domain/repositories/tts_repository.dart';
import 'package:lectorsync/features/reader/presentation/pages/reader_page.dart';
import 'package:lectorsync/features/settings/domain/entities/reading_preferences.dart';
import 'package:lectorsync/features/settings/domain/repositories/preferences_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _code = 'def trabajo(f, d):\n    return f * d  # una línea larga que no se parte';

final _blocks = [
  const ChapterBlock.heading('Ejercicio 1'),
  const ChapterBlock.paragraph('Para mantener estirado un resorte se requiere '
      'una fuerza.'),
  const ChapterBlock.code(_code),
  ChapterBlock.figure(
    page: 0,
    rect: const PageRect(150, 200, 300, 230),
    figureKind: FigureKind.formula,
    textHeight: 11,
  ),
];

Chapter _chapter() {
  final text = Chapter.textOfBlocks(_blocks);
  final words = text.split(RegExp(r'\s+'));
  return Chapter(
    id: 'ch-0001',
    title: 'Sección 1',
    orderIndex: 0,
    wordCount: words.length,
    text: text,
    words: words,
    blocks: _blocks,
  );
}

class _FakeReaderRepository implements ReaderRepository {
  @override
  Future<Either<Failure, List<Chapter>>> getChapters(String bookId) async {
    final c = _chapter();
    return right([
      Chapter(
        id: c.id,
        title: c.title,
        orderIndex: c.orderIndex,
        wordCount: c.wordCount,
      ),
    ]);
  }

  @override
  Future<Either<Failure, Chapter>> getChapter({
    required String bookId,
    required String chapterId,
  }) async => right(_chapter());

  @override
  Future<Either<Failure, bool>> saveProgress({
    required String bookId,
    required String chapterId,
    required int wordIndex,
  }) async => right(true);

  @override
  Future<Either<Failure, ChapterAudio>> getChapterAudio({
    required String bookId,
    required String chapterId,
    String voiceId = '21m00Tcm4TlvDq8ikWAW',
    String provider = 'mock',
  }) async => left(const ServerFailure());
}

class _FakeTtsRepository implements TtsRepository {
  final _statusCtrl = StreamController<TtsPlaybackStatus>.broadcast();
  final _wordCtrl = StreamController<int>.broadcast();

  @override
  Stream<int> get wordIndexStream => _wordCtrl.stream;

  @override
  Stream<TtsPlaybackStatus> get statusStream => _statusCtrl.stream;

  @override
  TtsPlaybackStatus get currentStatus => TtsPlaybackStatus.idle;

  @override
  Future<Either<Failure, Unit>> initialize() async => right(unit);

  @override
  Future<Either<Failure, Unit>> speak({
    required String text,
    required List<String> words,
    int startWordIndex = 0,
    List<ChapterBlock> blocks = const [],
  }) async => right(unit);

  @override
  Future<Either<Failure, Unit>> stop() async => right(unit);

  @override
  Future<Either<Failure, Unit>> setLanguage(String languageCode) async =>
      right(unit);

  @override
  Future<void> dispose() async {}
}

class _FakeDeviceTts extends Fake implements DeviceTtsRepository {
  @override
  Stream<bool> get estimatingStream => const Stream<bool>.empty();
}

class _FakePreferencesRepository implements PreferencesRepository {
  @override
  Future<ReadingPreferences> load() async => const ReadingPreferences();

  @override
  Future<void> save(ReadingPreferences preferences) async {}
}

class _FakeFullscreen implements SystemFullscreen {
  @override
  Future<void> init() async {}

  @override
  Future<void> enter() async {}

  @override
  Future<void> exit() async {}
}

class _FakeQuietMode implements QuietMode {
  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> hasAccess() async => false;

  @override
  Future<void> openAccessSettings() async {}

  @override
  Future<bool> activate() async => false;

  @override
  Future<void> deactivate() async {}
}

class _FakeFocusPrefs implements FocusPrefs {
  @override
  Future<bool> isSet(String key) async => false;

  @override
  Future<void> set(String key) async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sl
      ..registerSingleton<ReaderRepository>(_FakeReaderRepository())
      ..registerSingleton<TtsRepository>(_FakeTtsRepository())
      ..registerSingleton<DeviceTtsRepository>(_FakeDeviceTts())
      ..registerSingleton<PreferencesRepository>(_FakePreferencesRepository())
      ..registerSingleton<BookmarkRepository>(BookmarkRepository())
      ..registerSingleton<SystemFullscreen>(_FakeFullscreen())
      ..registerSingleton<QuietMode>(_FakeQuietMode())
      ..registerSingleton<FocusPrefs>(_FakeFocusPrefs());
  });

  tearDown(() async {
    await sl.reset();
  });

  Future<void> pumpReader(WidgetTester tester) async {
    // Alto de móvil: la lista solo construye lo que cabe en pantalla.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: ReaderPage(bookId: 'libro', bookTitle: 'Libro')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('el código va en monoespaciada, sin partir y con desplazamiento '
      'horizontal', (tester) async {
    await pumpReader(tester);

    final code = tester.widget<Text>(find.text(_code));
    expect(code.style?.fontFamily, 'monospace');
    expect(code.softWrap, isFalse);
    final scroll = tester.widget<SingleChildScrollView>(
      find.ancestor(
        of: find.text(_code),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scroll.scrollDirection, Axis.horizontal);
  });

  testWidgets('el título sale en seminegrita', (tester) async {
    await pumpReader(tester);

    final heading = tester.widget<Text>(find.text('Ejercicio 1'));
    expect(heading.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('la figura ocupa su sitio con la proporción del recorte mientras '
      'no hay imagen', (tester) async {
    await pumpReader(tester);

    // 150 × 30 pt con la letra del libro (11 pt) a la del lector (18 px).
    const width = 150 * 18 / 11;
    const height = width * 30 / 150;
    final placeholder = find.byWidgetPredicate((w) =>
        w is SizedBox &&
        (w.width ?? 0).toStringAsFixed(2) == width.toStringAsFixed(2) &&
        (w.height ?? 0).toStringAsFixed(2) == height.toStringAsFixed(2));
    expect(placeholder, findsOneWidget);
    expect(find.bySemanticsLabel('Fórmula'), findsOneWidget);
  });
}
