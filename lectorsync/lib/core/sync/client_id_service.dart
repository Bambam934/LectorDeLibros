import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Generates and caches a stable per-install device identifier that the
/// backend uses to attribute realtime-sync writes back to their origin.
///
/// Why a UUID and not, say, a device serial?
///
///  - We need it to survive app updates and re-logins (so peers can
///    still recognise our echoes).
///  - We must NOT use a hardware identifier — that would be a privacy
///    foot-gun and on iOS / Web there is no reliable one anyway.
///  - One ID per install (NOT per account) so signing out and back in
///    keeps the same channel attribution. If the user reinstalls or
///    clears app data they get a new ID, which is harmless.
///
/// The first call writes a freshly-minted v4 UUID to SharedPreferences
/// and caches it in memory; subsequent calls are zero-IO.
class ClientIdService {
  ClientIdService({Uuid? uuid, SharedPreferences? prefs})
      : _uuid = uuid ?? const Uuid(),
        _prefsOverride = prefs;

  static const String prefsKey = 'sync.client_id';

  final Uuid _uuid;
  final SharedPreferences? _prefsOverride;

  String? _cached;
  Completer<String>? _inflight;

  /// Returns the persisted clientId, creating one on first access.
  /// Concurrent callers share the same in-flight future so we never
  /// race and write two different UUIDs from parallel `getId()` calls
  /// during cold-start initialisation.
  Future<String> getId() async {
    final cached = _cached;
    if (cached != null) return cached;

    final inflight = _inflight;
    if (inflight != null) return inflight.future;

    final completer = Completer<String>();
    _inflight = completer;
    try {
      final prefs = _prefsOverride ?? await SharedPreferences.getInstance();
      var id = prefs.getString(prefsKey);
      if (id == null || id.isEmpty) {
        id = _uuid.v4();
        await prefs.setString(prefsKey, id);
      }
      _cached = id;
      completer.complete(id);
      return id;
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _inflight = null;
    }
  }

  /// Synchronous accessor — returns null if [getId] has not finished
  /// yet. Used by the Dio interceptor: if the cache isn't warm, the
  /// request goes out without the header (the realtime event will then
  /// be treated as fresh on every peer including ourselves, which is
  /// harmless on a first request).
  String? get cachedId => _cached;

  /// Test/CI helper.
  void debugReset() {
    _cached = null;
    _inflight = null;
  }
}
