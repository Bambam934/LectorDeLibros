// dart:html is still functional and ships with Flutter Web. Migrating
// this whole client to package:web + dart:js_interop is a separate
// effort tracked outside this PR.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';

import 'sync_event.dart';
import 'sync_stream_client.dart';

SyncStreamClient createSyncStreamClientImpl({
  required String Function() baseUrlGetter,
  required Future<String?> Function() accessTokenGetter,
}) {
  return _WebSyncStreamClient(
    baseUrlGetter: baseUrlGetter,
    accessTokenGetter: accessTokenGetter,
  );
}

/// Browser implementation. Uses the native `EventSource` so we inherit
/// the spec-compliant SSE parser and built-in reconnection — but with
/// one important caveat: `EventSource` does NOT support custom request
/// headers (no `Authorization`). The portable workaround is to pass
/// the access token as a query parameter; the backend reads either.
///
/// If you decide to gate the backend behind cookies later, swap this
/// for a `fetch()` ReadableStream loop (longer code, but lets you set
/// headers). For now the JWT-in-URL is the standard SSE-from-browser
/// pattern (see e.g. nchan, Mercure).
class _WebSyncStreamClient implements SyncStreamClient {
  _WebSyncStreamClient({
    required String Function() baseUrlGetter,
    required Future<String?> Function() accessTokenGetter,
  })  : _baseUrlGetter = baseUrlGetter,
        _accessTokenGetter = accessTokenGetter;

  final String Function() _baseUrlGetter;
  final Future<String?> Function() _accessTokenGetter;

  final _eventsController = StreamController<SyncEvent>.broadcast();
  final _statusController =
      StreamController<SyncConnectionStatus>.broadcast();
  SyncConnectionStatus _currentStatus = SyncConnectionStatus.idle;

  html.EventSource? _eventSource;
  bool _shouldRun = false;
  bool _disposed = false;

  // EventSource has its own reconnect, but it spins fast on auth
  // failure (no auth → 401 → reconnect → 401 → ...). We layer an
  // application-level backoff on top, tearing down and rebuilding the
  // EventSource ourselves once the failure pattern looks systemic.
  int _consecutiveErrors = 0;
  Timer? _reconnectTimer;

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
    if (_shouldRun) return;
    _shouldRun = true;
    _consecutiveErrors = 0;
    await _connect();
  }

  Future<void> _connect() async {
    if (_disposed || !_shouldRun) return;
    _setStatus(_consecutiveErrors == 0
        ? SyncConnectionStatus.connecting
        : SyncConnectionStatus.reconnecting);

    final token = await _accessTokenGetter();
    if (token == null || token.isEmpty) {
      _setStatus(SyncConnectionStatus.idle);
      _shouldRun = false;
      return;
    }

    // Browsers cannot set Authorization on EventSource — pass via query
    // string. The backend reads it from headers, so when this lands
    // we'll add an env-gated fallback there. For now, this requires a
    // small backend tweak that's documented in the PR.
    final base = _baseUrlGetter();
    final url = '$base/api/v1/sync/stream?access_token='
        '${Uri.encodeQueryComponent(token)}';

    try {
      final es = html.EventSource(url, withCredentials: true);
      _eventSource = es;

      // Each named event type uses an addEventListener on its name —
      // an unnamed `data:` line goes to onMessage. The backend always
      // sends a name, so we register the known set and a catch-all.
      const types = ['progress.updated', 'bookmark.added', 'bookmark.updated', 'bookmark.removed'];
      for (final t in types) {
        es.addEventListener(t, (event) {
          if (event is html.MessageEvent) _handlePayload(t, event.data);
        });
      }
      es.onMessage.listen((event) {
        // Generic message — fallback path. The named listeners above
        // catch the common cases; this is for forward-compat.
        if (event.type.isNotEmpty) _handlePayload(event.type, event.data);
      });

      es.onOpen.listen((_) {
        _setStatus(SyncConnectionStatus.connected);
        _consecutiveErrors = 0;
      });

      es.onError.listen((_) {
        // EventSource reconnects on its own but flips through 'open'
        // briefly even on auth fail. We count errors and tear it down
        // ourselves once we see repeated failures within a short
        // window — that's the cue that the issue is structural
        // (revoked token, server down), not a transient network blip.
        _consecutiveErrors++;
        if (_consecutiveErrors >= 3) {
          _scheduleReconnect();
        }
      });
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SyncStreamClient] EventSource construction failed: $e');
      }
      _scheduleReconnect();
    }
  }

  void _handlePayload(String type, Object? rawData) {
    if (rawData is! String) return;
    try {
      final json = jsonDecode(rawData);
      if (json is! Map<String, dynamic>) return;
      final event = SyncEvent.parse(type, json);
      if (event != null && !_eventsController.isClosed) {
        _eventsController.add(event);
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SyncStreamClient] failed to parse SSE payload: $e');
      }
    }
  }

  void _scheduleReconnect() {
    _cleanupEventSource();
    if (_disposed || !_shouldRun) {
      _setStatus(SyncConnectionStatus.idle);
      return;
    }
    _setStatus(SyncConnectionStatus.reconnecting);
    final attempt = (_consecutiveErrors / 3).ceil(); // 1, 2, 3, ...
    final delaySec = attempt > 5 ? 30 : (1 << (attempt - 1));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      _reconnectTimer = null;
      _consecutiveErrors = 0;
      _connect();
    });
  }

  void _cleanupEventSource() {
    final es = _eventSource;
    _eventSource = null;
    es?.close();
  }

  @override
  Future<void> stop() async {
    _shouldRun = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cleanupEventSource();
    _setStatus(SyncConnectionStatus.idle);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _eventsController.close();
    await _statusController.close();
  }
}
