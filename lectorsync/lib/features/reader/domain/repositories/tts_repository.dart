import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/chapter_block.dart';

enum TtsPlaybackStatus { idle, loading, playing, error, completed }

abstract interface class TtsRepository {
  Stream<int> get wordIndexStream;
  Stream<TtsPlaybackStatus> get statusStream;
  TtsPlaybackStatus get currentStatus;

  Future<Either<Failure, Unit>> initialize();

  /// [blocks] es la maquetación del capítulo (ADR 13), si la tiene: con ella
  /// la voz dice "Fórmula." o "Bloque de código." en vez de leer lo que la
  /// pantalla enseña aparte. Las voces de servidor la ignoran.
  Future<Either<Failure, Unit>> speak({
    required String text,
    required List<String> words,
    int startWordIndex = 0,
    List<ChapterBlock> blocks = const [],
  });

  Future<Either<Failure, Unit>> stop();

  Future<Either<Failure, Unit>> setLanguage(String languageCode);

  Future<void> dispose();
}
