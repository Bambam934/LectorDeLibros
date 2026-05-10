import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/book.dart';
import '../../domain/repositories/library_repository.dart';

class RemoteLibraryRepository implements LibraryRepository {
  RemoteLibraryRepository({required ApiClient apiClient}) : _dio = apiClient.dio;

  final Dio _dio;

  DioMediaType _contentTypeFor(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'epub' => DioMediaType('application', 'epub+zip'),
      'pdf' => DioMediaType('application', 'pdf'),
      'txt' => DioMediaType('text', 'plain'),
      'md' || 'markdown' => DioMediaType('text', 'markdown'),
      _ => DioMediaType('application', 'octet-stream'),
    };
  }

  @override
  Future<Either<Failure, List<Book>>> getBooks() async {
    try {
      final response = await _dio.get('/api/v1/library');
      if (response.statusCode != 200) {
        return Left(ServerFailure('No se pudo cargar la biblioteca.'));
      }
      final data = response.data;
      if (data is! List) {
        return Left(ServerFailure('Respuesta inesperada del servidor.'));
      }
      final books = data
          .whereType<Map<String, dynamic>>()
          .map(Book.fromJson)
          .toList(growable: false);
      return Right(books);
    } on DioException catch (e) {
      return Left(ServerFailure(_messageFor(e, 'No se pudo conectar al servidor.')));
    }
  }

  @override
  Future<Either<Failure, Book>> importBook({
    required String filename,
    required Uint8List bytes,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: _contentTypeFor(filename),
        ),
      });

      final response = await _dio.post(
        '/api/v1/library/import',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (response.statusCode == 201 || response.statusCode == 202) {
        final data = response.data as Map<String, dynamic>;
        return Right(Book.fromJson(data));
      }
      return Left(ServerFailure('No se pudo importar el libro.'));
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400) {
        final msg = (e.response?.data is Map<String, dynamic>)
            ? (e.response!.data['message'] as String? ?? 'Archivo inválido.')
            : 'Archivo inválido.';
        return Left(FileFailure(msg));
      }
      return Left(ServerFailure(_messageFor(e, 'No se pudo subir el archivo.')));
    }
  }

  @override
  Future<Either<Failure, bool>> deleteBook(String id) async {
    try {
      final response = await _dio.delete('/api/v1/books/$id');
      if (response.statusCode == 204) {
        return const Right(true);
      }
      return Left(ServerFailure('No se pudo eliminar el libro.'));
    } on DioException catch (e) {
      return Left(ServerFailure(_messageFor(e, 'No se pudo eliminar el libro.')));
    }
  }

  String _messageFor(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final msg = data['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    return fallback;
  }
}
