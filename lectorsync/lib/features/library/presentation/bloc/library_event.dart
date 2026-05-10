import 'dart:typed_data';

import 'package:equatable/equatable.dart';

abstract class LibraryEvent extends Equatable {
  const LibraryEvent();

  @override
  List<Object> get props => [];
}

class LibraryFetched extends LibraryEvent {}

class LibraryBookImported extends LibraryEvent {
  const LibraryBookImported({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;

  @override
  List<Object> get props => [filename, bytes];
}

class LibraryBookDeleted extends LibraryEvent {
  const LibraryBookDeleted(this.bookId);
  final String bookId;

  @override
  List<Object> get props => [bookId];
}
