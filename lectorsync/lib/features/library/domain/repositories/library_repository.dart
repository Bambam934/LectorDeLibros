import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import '../../../../core/errors/failures.dart';
import '../entities/book.dart';

abstract interface class LibraryRepository {
  Future<Either<Failure, List<Book>>> getBooks();

  Future<Either<Failure, Book>> importBook({
    required String filename,
    required Uint8List bytes,
  });

  Future<Either<Failure, bool>> deleteBook(String id);
}
