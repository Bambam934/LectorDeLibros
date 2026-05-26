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

/// Dispatched by [ReaderBloc] itself when its subscription to the
/// realtime sync stream surfaces a `progress.updated` event for the
/// currently open book that ORIGINATED on another device. The handler
/// stashes a [PendingRemoteProgress] into the state for the UI to
/// surface; the user then chooses to apply it via
/// [ReaderRemoteProgressAccepted] or to dismiss it via
/// [ReaderRemoteProgressDismissed].
///
/// Constructor is public so test code can inject synthesised events.
class ReaderRemoteProgressReceived extends ReaderEvent {
  const ReaderRemoteProgressReceived({
    required this.chapterId,
    required this.wordIndex,
    required this.lastReadAt,
  });

  final String chapterId;
  final int wordIndex;
  final String lastReadAt;

  @override
  List<Object?> get props => [chapterId, wordIndex, lastReadAt];
}

/// User tapped "Ir allí" on the remote-progress snackbar — apply the
/// pending update (navigate chapters if needed, set wordIndex,
/// optionally pause TTS).
class ReaderRemoteProgressAccepted extends ReaderEvent {
  const ReaderRemoteProgressAccepted();
}

/// User dismissed the remote-progress snackbar — drop the pending
/// update without applying it. Local position stays where it was.
class ReaderRemoteProgressDismissed extends ReaderEvent {
  const ReaderRemoteProgressDismissed();
}
