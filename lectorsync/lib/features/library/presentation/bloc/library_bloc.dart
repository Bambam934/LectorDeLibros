import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/library_repository.dart';
import 'library_event.dart';
import 'library_state.dart';

class LibraryBloc extends Bloc<LibraryEvent, LibraryState> {
  LibraryBloc({required LibraryRepository libraryRepository})
      : _libraryRepository = libraryRepository,
        super(const LibraryState()) {
    on<LibraryFetched>(_onFetched);
    on<LibraryBookImported>(_onBookImported);
    on<LibraryBookDeleted>(_onBookDeleted);
  }

  final LibraryRepository _libraryRepository;

  Future<void> _onFetched(
    LibraryFetched event,
    Emitter<LibraryState> emit,
  ) async {
    emit(state.copyWith(status: LibraryStatus.loading));
    final result = await _libraryRepository.getBooks();
    result.fold(
      (failure) => emit(state.copyWith(
        status: LibraryStatus.failure,
        errorMessage: failure.message,
      )),
      (books) => emit(state.copyWith(
        status: LibraryStatus.success,
        books: books,
      )),
    );
  }

  Future<void> _onBookImported(
    LibraryBookImported event,
    Emitter<LibraryState> emit,
  ) async {
    emit(state.copyWith(status: LibraryStatus.loading));
    final result = await _libraryRepository.importBook(
      filename: event.filename,
      bytes: event.bytes,
    );
    result.fold(
      (failure) => emit(state.copyWith(
        status: LibraryStatus.failure,
        errorMessage: failure.message,
      )),
      (_) => add(LibraryFetched()),
    );
  }

  Future<void> _onBookDeleted(
    LibraryBookDeleted event,
    Emitter<LibraryState> emit,
  ) async {
    final result = await _libraryRepository.deleteBook(event.bookId);
    result.fold(
      (failure) => emit(state.copyWith(
        status: LibraryStatus.failure,
        errorMessage: failure.message,
      )),
      (_) => add(LibraryFetched()),
    );
  }
}
