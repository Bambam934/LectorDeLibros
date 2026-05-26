import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;

import 'sync_event.dart';
import 'sync_stream_client_stub.dart'
    if (dart.library.html) 'sync_stream_client_web.dart'
    if (dart.library.io) 'sync_stream_client_io.dart';

/// Public surface of the realtime sync transport. Concrete impls live
/// in platform-specific files behind conditional imports:
///
///  - Web: uses the browser's native `EventSource`, which gives us
///    automatic reconnection and the standard SSE parser for free.
///  - IO (Android / iOS / Windows / macOS / Linux): uses `dart:io`'s
///    `HttpClient` with chunked reading and our own SSE frame parser,
///    plus a hand-rolled exponential reconnect loop.
///
/// The factory [createSyncStreamClient] returns the right one. Callers
/// program against this abstract class so the rest of the app is
/// transport-agnostic.
abstract class SyncStreamClient {
  /// Emits parsed [SyncEvent]s as they arrive. Welcome frames are
  /// already filtered out by [SyncEvent.parse]. Errors on the underlying
  /// stream do NOT propagate here — they trigger an internal reconnect
  /// attempt instead, because the consumer (a bloc / cubit) should
  /// never have to know that the socket flapped.
  Stream<SyncEvent> get events;

  /// Connection status. Useful for showing a "disconnected" pill in
  /// the UI when the network goes flaky for long enough that the
  /// reconnect backoff has stretched out.
  Stream<SyncConnectionStatus> get status;
  SyncConnectionStatus get currentStatus;

  /// Opens (or re-opens) the SSE channel. Idempotent; calling [start]
  /// while already connected is a no-op. The auth token is read at the
  /// moment of each (re)connect, so a fresh access token from a
  /// background refresh is automatically picked up.
  Future<void> start();

  /// Tears down the channel and cancels any pending reconnect timer.
  /// Idempotent.
  Future<void> stop();

  Future<void> dispose();
}

enum SyncConnectionStatus { idle, connecting, connected, reconnecting, failed }

/// Public factory injected via DI. Defined in this file so callers
/// have a single import path.
SyncStreamClient createSyncStreamClient({
  required String Function() baseUrlGetter,
  required Future<String?> Function() accessTokenGetter,
}) {
  return createSyncStreamClientImpl(
    baseUrlGetter: baseUrlGetter,
    accessTokenGetter: accessTokenGetter,
  );
}

/// Shared bits used by both io and web impls. NOT exported through
/// `package:` — internal to the sync module.

/// Parses a single SSE "frame" (text up to a blank line) into a typed
/// event. Returns null if the frame is malformed, a heartbeat comment,
/// or a welcome frame. Exported so the io-impl can call it; tests do
/// too. NOT for app code — go through [SyncStreamClient.events] instead.
SyncEvent? parseSseFrame(String frame) {
  String? eventType;
  final dataLines = <String>[];

  for (final rawLine in const LineSplitter().convert(frame)) {
    final line = rawLine.trimRight();
    if (line.isEmpty || line.startsWith(':')) continue; // comment / heartbeat
    final colonIdx = line.indexOf(':');
    if (colonIdx < 0) continue;
    final field = line.substring(0, colonIdx);
    var value = line.substring(colonIdx + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'event':
        eventType = value;
        break;
      case 'data':
        dataLines.add(value);
        break;
      // `id:` and `retry:` exist in the spec but the backend doesn't
      // emit them; intentionally ignored.
    }
  }

  if (eventType == null || dataLines.isEmpty) return null;
  final raw = dataLines.join('\n');
  try {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) return null;
    return SyncEvent.parse(eventType, json);
  } catch (e) {
    if (kDebugMode) {
      // Don't crash the stream on a malformed frame — just drop it.
      // ignore: avoid_print
      print('[SyncStreamClient] failed to parse SSE frame: $e raw="$raw"');
    }
    return null;
  }
}
