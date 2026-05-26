import 'package:equatable/equatable.dart';

/// Strongly-typed mirror of the backend `RealtimeEvent` shape (see
/// `backend/src/core/realtime-bus.ts`). The frontend only consumes
/// events; we never publish, so parsing is one-way.
sealed class SyncEvent extends Equatable {
  const SyncEvent({required this.type, required this.ts, this.clientId});

  /// Event type discriminator — matches the SSE `event:` line.
  final String type;

  /// ISO-8601 server timestamp at publish time. Use for last-write-wins
  /// reconciliation when multiple devices race.
  final String ts;

  /// UUID of the device that triggered the write. Null for events not
  /// originated by a user action (heartbeats, server maintenance).
  /// Frontend uses this to discard echoes of its own writes by
  /// comparing against `ClientIdService.cachedId`.
  final String? clientId;

  /// True iff this event was emitted by THIS device. The caller is
  /// expected to pass its own clientId; we don't reach into the DI
  /// container to avoid a circular dep.
  bool isEchoOf(String? myClientId) =>
      clientId != null && myClientId != null && clientId == myClientId;

  @override
  List<Object?> get props => [type, ts, clientId];

  /// Factory dispatch on the SSE `event:` line value. Unknown event
  /// types fall back to [SyncUnknownEvent] instead of throwing — the
  /// backend may publish new event types ahead of a client update and
  /// we want the SSE stream to keep flowing.
  static SyncEvent? parse(String eventType, Map<String, dynamic> json) {
    final ts = json['ts']?.toString() ?? '';
    final clientId = json['clientId']?.toString();
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : <String, dynamic>{};

    // Welcome frame: the backend sends one immediately on connect so
    // clients can detect "channel open". It carries the user id but no
    // business payload. Skip rather than dispatch to listeners.
    if (data['__welcome'] == true) return null;

    switch (eventType) {
      case 'progress.updated':
        return SyncProgressUpdatedEvent(
          ts: ts,
          clientId: clientId,
          bookId: data['bookId']?.toString() ?? '',
          chapterId: data['chapterId']?.toString() ?? '',
          wordIndex: _asInt(data['wordIndex']) ?? 0,
          audioPositionMs: _asInt(data['audioPositionMs']) ?? 0,
          percentage: _asDouble(data['percentage']) ?? 0,
          lastReadAt: data['lastReadAt']?.toString() ?? ts,
        );
      case 'bookmark.added':
      case 'bookmark.updated':
      case 'bookmark.removed':
        return SyncBookmarkEvent(
          type: eventType,
          ts: ts,
          clientId: clientId,
          data: data,
        );
      default:
        return SyncUnknownEvent(type: eventType, ts: ts, clientId: clientId);
    }
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static double? _asDouble(Object? v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

class SyncProgressUpdatedEvent extends SyncEvent {
  const SyncProgressUpdatedEvent({
    required super.ts,
    super.clientId,
    required this.bookId,
    required this.chapterId,
    required this.wordIndex,
    required this.audioPositionMs,
    required this.percentage,
    required this.lastReadAt,
  }) : super(type: 'progress.updated');

  final String bookId;
  final String chapterId;
  final int wordIndex;
  final int audioPositionMs;
  final double percentage;
  final String lastReadAt;

  @override
  List<Object?> get props =>
      [...super.props, bookId, chapterId, wordIndex, audioPositionMs, percentage, lastReadAt];
}

class SyncBookmarkEvent extends SyncEvent {
  const SyncBookmarkEvent({
    required super.type,
    required super.ts,
    super.clientId,
    required this.data,
  });

  /// Raw payload — schema not stabilised yet (bookmarks backend is
  /// being added in parallel). When the contract is final this becomes
  /// a strongly-typed class.
  final Map<String, dynamic> data;

  @override
  List<Object?> get props => [...super.props, data];
}

class SyncUnknownEvent extends SyncEvent {
  const SyncUnknownEvent({
    required super.type,
    required super.ts,
    super.clientId,
  });
}
