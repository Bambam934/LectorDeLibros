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
    // La operación en curso (si la hay) NO se toca aquí: este refetch es el
    // último tramo de la importación o el borrado, y el aviso debe seguir en
    // pantalla hasta que la lista esté lista. Se limpia abajo, con el
    // resultado ya emitido.
    emit(state.copyWith(status: LibraryStatus.loading));
    final result = await _libraryRepository.getBooks();
    result.fold(
      (failure) => emit(state.copyWith(
        status: LibraryStatus.failure,
        operation: LibraryOperation.none,
        errorMessage: failure.message,
        clearPendingFilename: true,
      )),
      (books) => emit(state.copyWith(
        status: LibraryStatus.success,
        operation: LibraryOperation.none,
        books: books,
        clearErrorMessage: true,
        clearPendingFilename: true,
      )),
    );
  }

  Future<void> _onBookImported(
    LibraryBookImported event,
    Emitter<LibraryState> emit,
  ) async {
    // Una operación con nombre, no un `loading` anónimo: la pantalla muestra
    // el archivo y avisa de que el análisis puede tardar, en vez de dejar la
    // biblioteca aparentemente colgada mientras se extrae el texto del PDF.
    emit(state.copyWith(
      operation: LibraryOperation.importing,
      pendingFilename: event.filename,
    ));
    final result = await _libraryRepository.importBook(
      filename: event.filename,
      bytes: event.bytes,
    );
    result.fold(
      (failure) => emit(state.copyWith(
        status: LibraryStatus.failure,
        operation: LibraryOperation.none,
        errorMessage: failure.message,
        clearPendingFilename: true,
      )),
      // El aviso sigue puesto durante el refetch; `_onFetched` lo retira
      // cuando el libro nuevo ya está en la lista.
      (_) => add(LibraryFetched()),
    );
  }

  Future<void> _onBookDeleted(
    LibraryBookDeleted event,
    Emitter<LibraryState> emit,
  ) async {
    emit(state.copyWith(operation: LibraryOperation.deleting));
    final result = await _libraryRepository.deleteBook(event.bookId);
    result.fold(
      (failure) => emit(state.copyWith(
        status: LibraryStatus.failure,
        operation: LibraryOperation.none,
        errorMessage: failure.message,
      )),
      (_) => add(LibraryFetched()),
    );
  }
}
