import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:lectorsync/core/errors/failures.dart';
import 'package:lectorsync/features/library/domain/entities/book.dart';
import 'package:lectorsync/features/library/domain/repositories/library_repository.dart';
import 'package:lectorsync/features/library/presentation/bloc/library_bloc.dart';
import 'package:lectorsync/features/library/presentation/bloc/library_event.dart';
import 'package:lectorsync/features/library/presentation/bloc/library_state.dart';

/// Repositorio con operaciones que no terminan hasta que el test las suelta.
///
/// Es lo que permite observar el estado **durante** la espera, que es justo
/// donde vivía el problema: sin control sobre el tiempo, importar terminaba
/// antes de poder comprobar qué se estaba mostrando.
class _SlowLibraryRepository implements LibraryRepository {
  final importGate = Completer<void>();
  final deleteGate = Completer<void>();

  static const _book = Book(id: 'b1', title: 'Ya importado');

  @override
  Future<Either<Failure, List<Book>>> getBooks() async => right([_book]);

  @override
  Future<Either<Failure, Book>> importBook({
    required String filename,
    required Uint8List bytes,
  }) async {
    await importGate.future;
    return right(const Book(id: 'b2', title: 'Recién importado'));
  }

  @override
  Future<Either<Failure, bool>> deleteBook(String id) async {
    await deleteGate.future;
    return right(true);
  }
}

void main() {
  late _SlowLibraryRepository repo;
  late LibraryBloc bloc;

  setUp(() {
    repo = _SlowLibraryRepository();
    bloc = LibraryBloc(libraryRepository: repo);
  });

  tearDown(() => bloc.close());

  group('estado durante la importación', () {
    test('se distingue de la carga normal del catálogo', () async {
      bloc.add(LibraryBookImported(
        filename: 'calculo.pdf',
        bytes: Uint8List(0),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.operation, LibraryOperation.importing);
      expect(bloc.state.isBusy, isTrue);
    });

    test('el aviso sobrevive al refetch que sigue a la importación',
        () async {
      // Regresión: el `LibraryFetched` que refresca la lista emitía `loading`
      // y, como importar era otro valor del MISMO enum, ese `loading` borraba
      // el `importing`. El overlay desaparecía a media operación y la
      // pantalla volvía a quedarse muda justo lo que el cambio quería evitar.
      bloc.add(LibraryBookImported(
        filename: 'calculo.pdf',
        bytes: Uint8List(0),
      ));
      await Future<void>.delayed(Duration.zero);

      repo.importGate.complete();
      // Primer estado del refetch: catálogo cargando, importación aún viva.
      final refetching = await bloc.stream.firstWhere(
        (s) => s.status == LibraryStatus.loading,
      );

      expect(refetching.operation, LibraryOperation.importing);
      expect(refetching.isBusy, isTrue);
    });

    test('recuerda el nombre del archivo para poder nombrarlo', () async {
      bloc.add(LibraryBookImported(
        filename: 'calculo.pdf',
        bytes: Uint8List(0),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.pendingFilename, 'calculo.pdf');
    });

    test('se marca como ocupado aunque ya haya libros en la lista', () async {
      // La regresión que arregla: la pantalla solo mostraba el indicador si
      // la biblioteca estaba vacía, así que importar el segundo libro no
      // producía ninguna señal visible.
      bloc.add(LibraryFetched());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.books, isNotEmpty);

      bloc.add(LibraryBookImported(
        filename: 'otro.pdf',
        bytes: Uint8List(0),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.isBusy, isTrue);
    });

    test('suelta el nombre del archivo al terminar', () async {
      bloc.add(LibraryBookImported(
        filename: 'calculo.pdf',
        bytes: Uint8List(0),
      ));
      await Future<void>.delayed(Duration.zero);

      repo.importGate.complete();
      await bloc.stream.firstWhere((s) => s.status == LibraryStatus.success);

      expect(bloc.state.pendingFilename, isNull);
      expect(bloc.state.isBusy, isFalse);
    });

    test('un fallo limpia el nombre y no deja la pantalla ocupada', () async {
      final failing = _FailingRepository();
      final b = LibraryBloc(libraryRepository: failing);
      addTearDown(b.close);

      b.add(LibraryBookImported(filename: 'roto.pdf', bytes: Uint8List(0)));
      await b.stream.firstWhere((s) => s.status == LibraryStatus.failure);

      expect(b.state.pendingFilename, isNull);
      expect(b.state.isBusy, isFalse);
      expect(b.state.errorMessage, isNotNull);
    });
  });

  group('estado durante el borrado', () {
    test('avisa mientras borra', () async {
      // Antes no emitía nada: el libro simplemente desaparecía cuando le
      // apetecía, sin señal de que la app estuviera haciendo algo.
      bloc.add(LibraryBookDeleted('b1'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.operation, LibraryOperation.deleting);
      expect(bloc.state.isBusy, isTrue);
    });

    test('vuelve a estado normal al acabar', () async {
      bloc.add(LibraryBookDeleted('b1'));
      await Future<void>.delayed(Duration.zero);

      repo.deleteGate.complete();
      await bloc.stream.firstWhere((s) => s.status == LibraryStatus.success);

      expect(bloc.state.isBusy, isFalse);
    });
  });

  test('el estado inicial no está ocupado', () {
    expect(const LibraryState().isBusy, isFalse);
  });

  group('errorMessage', () {
    test('se limpia al volver a cargar con éxito', () async {
      // Sin esto el mensaje solo podía fijarse, nunca borrarse: quedaba
      // pegado al estado tras un reintento con éxito y, como la pantalla
      // decide si enseñar el aviso comparando con el mensaje anterior, un
      // segundo fallo idéntico se quedaba sin aviso.
      const stale = LibraryState(
        status: LibraryStatus.failure,
        errorMessage: 'Error de red',
      );

      expect(stale.copyWith(clearErrorMessage: true).errorMessage, isNull);
    });

    test('un fallo tras un éxito vuelve a notificarse', () async {
      final repo = _FlakyRepository();
      final b = LibraryBloc(libraryRepository: repo);
      addTearDown(b.close);

      b.add(LibraryFetched());
      await b.stream.firstWhere((s) => s.status == LibraryStatus.failure);
      expect(b.state.errorMessage, 'Error de red');

      repo.shouldFail = false;
      b.add(LibraryFetched());
      await b.stream.firstWhere((s) => s.status == LibraryStatus.success);
      expect(b.state.errorMessage, isNull,
          reason: 'el éxito debe borrar el mensaje viejo');

      repo.shouldFail = true;
      b.add(LibraryFetched());
      final failed = await b.stream.firstWhere(
        (s) => s.status == LibraryStatus.failure,
      );

      // La pantalla compara prev.errorMessage con el nuevo: si el éxito no
      // hubiera limpiado, esta transición sería null→texto→texto y el
      // segundo aviso no se mostraría.
      expect(failed.errorMessage, 'Error de red');
    });
  });
}

/// Falla o no según le digan, para observar la secuencia fallo→éxito→fallo.
class _FlakyRepository implements LibraryRepository {
  bool shouldFail = true;

  @override
  Future<Either<Failure, List<Book>>> getBooks() async => shouldFail
      ? left(const ServerFailure('Error de red'))
      : right(const [Book(id: 'b1', title: 'Un libro')]);

  @override
  Future<Either<Failure, Book>> importBook({
    required String filename,
    required Uint8List bytes,
  }) async =>
      right(const Book(id: 'b2', title: 'Otro'));

  @override
  Future<Either<Failure, bool>> deleteBook(String id) async => right(true);
}

class _FailingRepository implements LibraryRepository {
  @override
  Future<Either<Failure, List<Book>>> getBooks() async => right(const []);

  @override
  Future<Either<Failure, Book>> importBook({
    required String filename,
    required Uint8List bytes,
  }) async => left(const FileFailure('Archivo ilegible'));

  @override
  Future<Either<Failure, bool>> deleteBook(String id) async => right(true);
}
