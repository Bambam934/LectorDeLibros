import 'package:equatable/equatable.dart';
import '../../domain/entities/book.dart';

/// Resultado de la última carga del catálogo.
enum LibraryStatus { initial, loading, success, failure }

/// Operación de escritura en curso, si la hay.
///
/// Va en un campo **aparte** de [LibraryStatus] —el mismo patrón que
/// `ReaderState.ttsStatus`— y no como valores extra del mismo enum. Mezclarlos
/// obligaba a que importar y recargar fueran estados excluyentes, y el
/// resultado era que el aviso se apagaba justo cuando aún hacía falta: al
/// terminar la importación, el `LibraryFetched` que refresca la lista emitía
/// `loading` y con ello borraba el `importing`, dejando la pantalla muda otra
/// vez mientras se releía el catálogo.
///
/// Separados, la operación sobrevive al refetch y se limpia cuando la lista
/// ya está en pantalla.
enum LibraryOperation { none, importing, deleting }

class LibraryState extends Equatable {
  const LibraryState({
    this.status = LibraryStatus.initial,
    this.operation = LibraryOperation.none,
    this.books = const [],
    this.errorMessage,
    this.pendingFilename,
  });

  final LibraryStatus status;
  final LibraryOperation operation;
  final List<Book> books;
  final String? errorMessage;

  /// Nombre del archivo que se está importando, para nombrarlo mientras se
  /// espera. Es `null` fuera de [LibraryOperation.importing].
  final String? pendingFilename;

  /// Hay una operación en curso que el usuario debe poder ver.
  bool get isBusy => operation != LibraryOperation.none;

  @override
  List<Object?> get props =>
      [status, operation, books, errorMessage, pendingFilename];

  LibraryState copyWith({
    LibraryStatus? status,
    LibraryOperation? operation,
    List<Book>? books,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? pendingFilename,
    bool clearPendingFilename = false,
  }) {
    return LibraryState(
      status: status ?? this.status,
      operation: operation ?? this.operation,
      books: books ?? this.books,
      // `clearErrorMessage` existe por la misma razón que en `ReaderState`:
      // sin él un mensaje solo podía fijarse, nunca borrarse, y quedaba
      // pegado al estado incluso tras un reintento con éxito. Como la pantalla
      // decide si enseñar el aviso comparando `prev.errorMessage` con el
      // nuevo, un segundo fallo con el mismo texto se quedaba sin aviso.
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      pendingFilename: clearPendingFilename
          ? null
          : (pendingFilename ?? this.pendingFilename),
    );
  }
}
