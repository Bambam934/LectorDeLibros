import 'sync_stream_client.dart';

/// Stub that should never run. Picked by the conditional import only
/// on platforms where neither `dart:io` nor `dart:html` is available
/// (e.g. an unusual build target). Throwing at construction time makes
/// the misconfiguration loud instead of silently never connecting.
SyncStreamClient createSyncStreamClientImpl({
  required String Function() baseUrlGetter,
  required Future<String?> Function() accessTokenGetter,
}) {
  throw UnsupportedError(
    'SyncStreamClient: no platform implementation available. '
    'Neither dart:io nor dart:html is supported on this build target.',
  );
}
