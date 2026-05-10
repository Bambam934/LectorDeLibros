import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/chapter.dart';
import '../../domain/entities/chapter_audio.dart';
import '../../domain/repositories/reader_repository.dart';

class RemoteReaderRepository implements ReaderRepository {
  RemoteReaderRepository({required ApiClient apiClient}) : _dio = apiClient.dio;

  final Dio _dio;

  @override
  Future<Either<Failure, List<Chapter>>> getChapters(String bookId) async {
    try {
      final response = await _dio.get('/api/v1/books/$bookId/chapters');
      if (response.statusCode != 200) {
        return Left(ServerFailure('No se pudo cargar la lista de capitulos.'));
      }

      final data = response.data;
      if (data is! List) {
        return Left(ServerFailure('Respuesta inesperada del servidor.'));
      }

      final chapters = data
          .whereType<Map<String, dynamic>>()
          .map(Chapter.fromSummaryJson)
          .toList(growable: false);

      return Right(chapters);
    } on DioException catch (e) {
      return Left(
        ServerFailure(_messageFor(e, 'No se pudo cargar los capitulos.')),
      );
    }
  }

  @override
  Future<Either<Failure, Chapter>> getChapter({
    required String bookId,
    required String chapterId,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/books/$bookId/chapters/$chapterId',
      );
      if (response.statusCode != 200) {
        return Left(ServerFailure('No se pudo cargar el capitulo.'));
      }

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return Left(ServerFailure('Respuesta inesperada del servidor.'));
      }

      return Right(Chapter.fromDetailJson(data));
    } on DioException catch (e) {
      return Left(
        ServerFailure(_messageFor(e, 'No se pudo cargar el capitulo.')),
      );
    }
  }

  @override
  Future<Either<Failure, bool>> saveProgress({
    required String bookId,
    required String chapterId,
    required int wordIndex,
  }) async {
    try {
      final response = await _dio.put(
        '/api/v1/books/$bookId/progress',
        data: {
          'chapter_id': chapterId,
          'word_index': wordIndex,
          'audio_position_ms': 0,
        },
      );

      if (response.statusCode == 204) {
        return const Right(true);
      }

      return Left(ServerFailure('No se pudo guardar el progreso de lectura.'));
    } on DioException catch (e) {
      return Left(
        ServerFailure(_messageFor(e, 'No se pudo guardar el progreso.')),
      );
    }
  }

  @override
  Future<Either<Failure, ChapterAudio>> getChapterAudio({
    required String bookId,
    required String chapterId,
    String voiceId = '21m00Tcm4TlvDq8ikWAW',
    String provider = 'mock',
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/books/$bookId/chapters/$chapterId/audio',
        data: {
          'voice_id': voiceId,
          'provider': provider,
        },
      );
      if (response.statusCode != 200) {
        return Left(ServerFailure('No se pudo obtener el audio del capitulo.'));
      }
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return Left(ServerFailure('Respuesta inesperada del servidor.'));
      }
      return Right(ChapterAudio.fromJson(data));
    } on DioException catch (e) {
      return Left(
        ServerFailure(_messageFor(e, 'No se pudo obtener el audio.')),
      );
    }
  }

  String _messageFor(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final msg = data['message'];
      if (msg is String && msg.isNotEmpty) {
        return msg;
      }
    }
    return fallback;
  }
}
