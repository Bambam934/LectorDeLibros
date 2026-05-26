import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'sync_event.dart';
import 'sync_stream_client.dart';

SyncStreamClient createSyncStreamClientImpl({
  required String Function() baseUrlGetter,
  required Future<String?> Function() accessTokenGetter,
}) {
  return _IoSyncStreamClient(
    baseUrlGetter: baseUrlGetter,
    accessTokenGetter: accessTokenGetter,
  );
}

class _IoSyncStreamClient implements SyncStreamClient {
  _IoSyncStreamClient({
    required String Function() baseUrlGetter,
    required Future<String?> Function() accessTokenGetter,
    HttpClient? httpClient,
  })  : _baseUrlGetter = baseUrlGetter,
        _accessTokenGetter = accessTokenGetter,
        // The HttpClient stays alive for the life of this client so
        // sockets stay pooled, and we set idleTimeout > heartbeat so
        // an idle SSE connection doesn't get reaped by the SDK.
        _httpClient = (httpClient ?? HttpClient())
          ..idleTimeout = const Duration(minutes: 5)
          ..connectionTimeout = const Duration(seconds: 10);

  final String Function() _baseUrlGetter;
  final Future<String?> Function() _accessTokenGetter;
  final HttpClient _httpClient;

  final _eventsController = StreamController<SyncEvent>.broadcast();
  final _statusController =
      StreamController<SyncConnectionStatus>.broadcast();
  SyncConnectionStatus _currentStatus = SyncConnectionStatus.idle;

  /// Currently-active SSE socket (request → response). Closing the
  /// request also closes the response, which is what we need to abort
  /// a long-poll cleanly on logout.
  HttpClientRequest? _activeRequest;
  StreamSubscription<List<int>>? _bodySub;

  /// Reconnect bookkeeping. The attempt counter is reset on every
  /// successful "connected" status emit so the backoff doesn't
  /// snowball across unrelated outages.
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  bool _shouldRun = false;
  bool _disposed = false;

  @override
  Stream<SyncEvent> get events => _eventsController.stream;

  @override
  Stream<SyncConnectionStatus> get status => _statusController.stream;

  @override
  SyncConnectionStatus get currentStatus => _currentStatus;

  void _setStatus(SyncConnectionStatus s) {
    _currentStatus = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  @override
  Future<void> start() async {
    if (_disposed) return;
    if (_shouldRun) return; // already running / scheduled
    _shouldRun = true;
    _reconnectAttempt = 0;
    await _connect();
  }

  Future<void> _connect() async {
    if (_disposed || !_shouldRun) return;

    _setStatus(_reconnectAttempt == 0
        ? SyncConnectionStatus.connecting
        : SyncConnectionStatus.reconnecting);

    final token = await _accessTokenGetter();
    if (token == null || token.isEmpty) {
      // No session yet — wait. Caller will re-invoke start() on login.
      _setStatus(SyncConnectionStatus.idle);
      _shouldRun = false;
      return;
    }

    final url = Uri.parse('${_baseUrlGetter()}/api/v1/sync/stream');

    HttpClientRequest? req;
    HttpClientResponse? resp;
    try {
      req = await _httpClient.getUrl(url);
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.acceptHeader, 'text/event-stream')
        ..set(HttpHeaders.cacheControlHeader, 'no-cache')
        // Disable Dart's request body buffering — SSE responses are
        // open-ended so we never want a content-length.
        ..chunkedTransferEncoding = false;
      _activeRequest = req;
      resp = await req.close();

      if (resp.statusCode != 200) {
        // 401: token expired during the long-poll window. Don't loop
        // tightly; back off like any other failure and let the next
        // attempt fetch a fresh token via [_accessTokenGetter].
        if (kDebugMode) {
          // ignore: avoid_print
          print('[SyncStreamClient] SSE returned status ${resp.statusCode}');
        }
        await resp.drain<void>().catchError((_) {});
        _scheduleReconnect();
        return;
      }

      _setStatus(SyncConnectionStatus.connected);
      _reconnectAttempt = 0; // success — reset backoff window

      final buffer = StringBuffer();
      final decoder = const Utf8Decoder(allowMalformed: true);

      _bodySub = resp.listen(
        (chunk) {
          buffer.write(decoder.convert(chunk));
          _drainBuffer(buffer);
        },
        onError: (Object e, StackTrace st) {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[SyncStreamClient] body stream error: $e');
          }
          _scheduleReconnect();
        },
        onDone: () {
          // Server closed the connection (or proxy timed it out).
          // Reconnect unless the caller explicitly stopped us.
          if (_shouldRun) _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SyncStreamClient] connect failed: $e');
      }
      _activeRequest = null;
      _scheduleReconnect();
    }
  }

  /// SSE frames are separated by a blank line ("\n\n"). Keep extracting
  /// complete frames out of [buffer] until the trailing bytes are
  /// incomplete, then leave them for the next chunk.
  void _drainBuffer(StringBuffer buffer) {
    var content = buffer.toString();
    while (true) {
      final idx = content.indexOf('\n\n');
      if (idx < 0) break;
      final frame = content.substring(0, idx);
      content = content.substring(idx + 2);
      final event = parseSseFrame(frame);
      if (event != null && !_eventsController.isClosed) {
        _eventsController.add(event);
      }
    }
    // Drop the consumed prefix back into the buffer.
    buffer
      ..clear()
      ..write(content);
  }

  void _scheduleReconnect() {
    _cleanupActiveSocket();
    if (_disposed || !_shouldRun) {
      _setStatus(SyncConnectionStatus.idle);
      return;
    }
    _setStatus(SyncConnectionStatus.reconnecting);
    _reconnectAttempt++;
    // Exponential backoff 1s, 2s, 4s, ... capped at 30s. The cap
    // prevents the user from waiting minutes after a long offline
    // window — once connectivity returns we want to be back fast.
    final delaySec = _reconnectAttempt > 5 ? 30 : (1 << (_reconnectAttempt - 1));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      _reconnectTimer = null;
      _connect();
    });
  }

  void _cleanupActiveSocket() {
    _bodySub?.cancel();
    _bodySub = null;
    final req = _activeRequest;
    _activeRequest = null;
    if (req != null) {
      // Close gracefully; ignore errors — we're already in cleanup.
      req.abort();
    }
  }

  @override
  Future<void> stop() async {
    _shouldRun = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cleanupActiveSocket();
    _setStatus(SyncConnectionStatus.idle);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    _httpClient.close(force: true);
    await _eventsController.close();
    await _statusController.close();
  }
}
