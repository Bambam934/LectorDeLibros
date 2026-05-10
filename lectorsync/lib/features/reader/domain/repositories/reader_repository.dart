import 'package:fpdart/fpdart.dart';
import '../../../../core/errors/failures.dart';
import '../entities/chapter.dart';
import '../entities/chapter_audio.dart';

abstract interface class ReaderRepository {
  Future<Either<Failure, List<Chapter>>> getChapters(String bookId);
  Future<Either<Failure, Chapter>> getChapter({
    required String bookId,
    required String chapterId,
  });
  Future<Either<Failure, bool>> saveProgress({
    required String bookId,
    required String chapterId,
    required int wordIndex,
  });
  Future<Either<Failure, ChapterAudio>> getChapterAudio({
    required String bookId,
    required String chapterId,
    String voiceId = '21m00Tcm4TlvDq8ikWAW',
    String provider = 'mock',
  });
}
