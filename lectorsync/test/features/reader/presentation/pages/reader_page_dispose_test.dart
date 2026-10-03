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
import 'package:lectorsync/features/reader/domain/repositories/reader_repository.dart';
import 'package:lectorsync/features/reader/domain/repositories/tts_repository.dart';
import 'package:lectorsync/features/reader/presentation/pages/reader_page.dart';
import 'package:lectorsync/features/settings/domain/entities/reading_preferences.dart';
import 'package:lectorsync/features/settings/domain/repositories/preferences_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTtsRepository implements TtsRepository {
  final statusCtrl = StreamController<TtsPlaybackStatus>.broadcast();
  final _wordCtrl = StreamController<int>.broadcast();

  int stopCalls = 0;

  @override
  Stream<int> get wordIndexStream => _wordCtrl.stream;

  @override
  Stream<TtsPlaybackStatus> get statusStream => statusCtrl.stream;

  @override
  TtsPlaybackStatus get currentStatus => TtsPlaybackStatus.idle;

  @override
  Future<Either<Failure, Unit>> initialize() async => right(unit);

  @override
  Future<Either<Failure, Unit>> speak({
    required String text,
    required List<String> words,
    int startWordIndex = 0,
  }) async => right(unit);

  @override
  Future<Either<Failure, Unit>> stop() async {
    stopCalls++;
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> setLanguage(String languageCode) async =>
      right(unit);

  @override
  Future<void> dispose() async {}
}

class _FakeReaderRepository implements ReaderRepository {
  @override
  Future<Either<Failure, List<Chapter>>> getChapters(String bookId) async =>
      right(const []);

  @override
  Future<Either<Failure, Chapter>> getChapter({
    required String bookId,
    required String chapterId,
  }) async => left(const CacheFailure());

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

/// Solo lo que el lector toca al montarse; el resto lanzaría.
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
  late _FakeTtsRepository tts;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tts = _FakeTtsRepository();
    sl
      ..registerSingleton<ReaderRepository>(_FakeReaderRepository())
      ..registerSingleton<TtsRepository>(tts)
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

  testWidgets(
    'cerrar el libro con la voz sonando cierra el bloc y para la voz',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ReaderPage(bookId: 'libro', bookTitle: 'Libro'),
        ),
      );
      await tester.pump();

      // La voz arranca: el cronómetro de la sesión de lectura se pone en
      // marcha, que es la rama de dispose() que leía el bloc del contexto.
      tts.statusCtrl.add(TtsPlaybackStatus.playing);
      await tester.pump();
      final stopsBefore = tts.stopCalls;

      // El usuario sale del lector sin parar la voz.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      // Con `context.read` en dispose() el elemento ya está desmontado: la
      // excepción abortaba el desmontaje, el BlocProvider no llegaba a
      // cerrar el bloc y la voz seguía leyendo fuera del libro.
      final error = tester.takeException();
      expect(tts.stopCalls, greaterThan(stopsBefore), reason: 'la voz sigue');
      expect(error, isNull);
    },
  );
}
