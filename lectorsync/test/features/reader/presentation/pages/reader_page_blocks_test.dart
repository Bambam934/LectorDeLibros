import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:lectorsync/features/reader/presentation/bloc/reader_bloc.dart';
import 'package:lectorsync/features/reader/presentation/bloc/reader_event.dart';
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
  const ChapterBlock.paragraph('1. Encontrar el área de la superficie. '
      'Después, comprobar el resultado.'),
];

Chapter _chapterOf(int index, List<ChapterBlock> blocks) {
  final text = Chapter.textOfBlocks(blocks);
  final words = text.split(RegExp(r'\s+'));
  return Chapter(
    id: 'ch-000${index + 1}',
    title: 'Sección ${index + 1}',
    orderIndex: index,
    wordCount: words.length,
    text: text,
    words: words,
    blocks: blocks,
  );
}

/// Un capítulo largo, de 60 párrafos de 12 palabras, para que haya que
/// desplazarse.
List<ChapterBlock> _longBlocks(String tag) => [
      for (var i = 0; i < 60; i++)
        ChapterBlock.paragraph(
            'Párrafo $i del capítulo $tag con texto suficiente para ocupar '
            'varias líneas.'),
    ];

class _FakeReaderRepository implements ReaderRepository {
  _FakeReaderRepository(List<List<ChapterBlock>> chapters)
      : _chapters = [
          for (var i = 0; i < chapters.length; i++) _chapterOf(i, chapters[i]),
        ];

  final List<Chapter> _chapters;

  @override
  Future<Either<Failure, List<Chapter>>> getChapters(String bookId) async =>
      right([
        for (final c in _chapters)
          Chapter(
            id: c.id,
            title: c.title,
            orderIndex: c.orderIndex,
            wordCount: c.wordCount,
          ),
      ]);

  @override
  Future<Either<Failure, Chapter>> getChapter({
    required String bookId,
    required String chapterId,
  }) async =>
      right(_chapters.firstWhere((c) => c.id == chapterId));

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

  Future<void> pumpReader(
    WidgetTester tester, {
    List<List<ChapterBlock>>? chapters,
    String? initialChapterId,
    int initialWordIndex = 0,
  }) async {
    sl.registerSingleton<ReaderRepository>(
      _FakeReaderRepository(chapters ?? [_blocks]),
    );
    // Alto de móvil: la lista solo construye lo que cabe en pantalla.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          bookId: 'libro',
          bookTitle: 'Libro',
          initialChapterId: initialChapterId,
          initialWordIndex: initialWordIndex,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Desplazamiento de la lista del capítulo (la única vertical).
  double scrollOffset(WidgetTester tester) => tester
      .state<ScrollableState>(find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down))
      .position
      .pixels;

  testWidgets('un número de lista no se separa de su elemento',
      (tester) async {
    await pumpReader(tester);

    expect(
      find.textContaining('1. Encontrar el área de la superficie.'),
      findsOneWidget,
    );
    expect(find.text('1.'), findsNothing);
  });

  testWidgets('la sangría desplaza solo la primera línea del párrafo',
      (tester) async {
    await pumpReader(tester);

    // Un hueco al principio del propio texto, no una fila con el texto al
    // lado (que sangraba la oración entera).
    final first = tester.widget<Text>(find.textContaining('1. Encontrar'));
    final spans = (first.textSpan! as TextSpan).children!;
    expect(spans.first, isA<WidgetSpan>());
    expect((spans.last as TextSpan).text,
        '1. Encontrar el área de la superficie.');
  });

  testWidgets('al abrir con una palabra guardada, la vista baja hasta ella',
      (tester) async {
    await pumpReader(
      tester,
      chapters: [_longBlocks('A')],
      initialChapterId: 'ch-0001',
      initialWordIndex: 600,
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(scrollOffset(tester), greaterThan(1000));
    expect(find.textContaining('Párrafo 50 del capítulo A'), findsOneWidget);
  });

  testWidgets('mover la posición sin voz lleva la vista hasta la palabra',
      (tester) async {
    await pumpReader(tester, chapters: [_longBlocks('A')]);
    expect(scrollOffset(tester), 0);

    BlocProvider.of<ReaderBloc>(tester.element(find.byType(ListView)))
        .add(const ReaderWordIndexChanged(600));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(scrollOffset(tester), greaterThan(1000));
    expect(find.textContaining('Párrafo 50 del capítulo A'), findsOneWidget);
  });

  testWidgets('al pasar de capítulo, el siguiente empieza arriba',
      (tester) async {
    await pumpReader(
      tester,
      chapters: [_longBlocks('A'), _longBlocks('B')],
      initialChapterId: 'ch-0001',
      initialWordIndex: 600,
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(scrollOffset(tester), greaterThan(1000));

    await tester.tap(find.text('Siguiente'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.textContaining('Párrafo 0 del capítulo B'), findsOneWidget);
    expect(scrollOffset(tester), 0);
  });

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
