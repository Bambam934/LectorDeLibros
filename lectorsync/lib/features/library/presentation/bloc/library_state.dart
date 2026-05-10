import 'package:equatable/equatable.dart';
import '../../domain/entities/book.dart';

enum LibraryStatus { initial, loading, success, failure }

class LibraryState extends Equatable {
  const LibraryState({
    this.status = LibraryStatus.initial,
    this.books = const [],
    this.errorMessage,
  });

  final LibraryStatus status;
  final List<Book> books;
  final String? errorMessage;

  @override
  List<Object?> get props => [status, books, errorMessage];

  LibraryState copyWith({
    LibraryStatus? status,
    List<Book>? books,
    String? errorMessage,
  }) {
    return LibraryState(
      status: status ?? this.status,
      books: books ?? this.books,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
