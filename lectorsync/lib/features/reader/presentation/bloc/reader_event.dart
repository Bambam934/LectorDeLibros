import 'package:equatable/equatable.dart';

abstract class ReaderEvent extends Equatable {
  const ReaderEvent();

  @override
  List<Object?> get props => [];
}

class ReaderStarted extends ReaderEvent {
  const ReaderStarted(
    this.bookId, {
    this.initialChapterId,
    this.initialWordIndex = 0,
  });

  final String bookId;
  final String? initialChapterId;
  final int initialWordIndex;

  @override
  List<Object?> get props => [bookId, initialChapterId, initialWordIndex];
}

class ReaderChapterSelected extends ReaderEvent {
  const ReaderChapterSelected(this.chapterId, {this.autoPlayTts = false});

  final String chapterId;
  final bool autoPlayTts;

  @override
  List<Object?> get props => [chapterId, autoPlayTts];
}

class ReaderWordIndexChanged extends ReaderEvent {
  const ReaderWordIndexChanged(this.wordIndex);

  final int wordIndex;

  @override
  List<Object?> get props => [wordIndex];
}

class ReaderProgressSaved extends ReaderEvent {
  const ReaderProgressSaved();
}

class ReaderTtsToggled extends ReaderEvent {
  const ReaderTtsToggled();
}

class ReaderTtsRestart extends ReaderEvent {
  const ReaderTtsRestart();
}
