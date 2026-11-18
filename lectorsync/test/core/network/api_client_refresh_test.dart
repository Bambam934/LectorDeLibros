import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/core/network/api_client.dart';
import 'package:lectorsync/core/storage/secure_storage.dart';

/// JWT sin firma válida: al cliente solo le importa el `exp` del payload.
String _jwt(DateTime expiresAt, String tag) {
  String part(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.'
      '${part({'exp': expiresAt.millisecondsSinceEpoch ~/ 1000, 'tag': tag})}.firma';
}

class _MemoryStorage extends SecureStorage {
  _MemoryStorage(this.access, this.refresh) : super(const FlutterSecureStorage());

  String? access;
  String? refresh;

  @override
  Future<void> saveTokens({required String access, required String refresh}) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<String?> getAccessToken() async => access;

  @override
  Future<String?> getRefreshToken() async => refresh;

  @override
  Future<void> clearTokens() async {
    access = null;
    refresh = null;
  }
}

/// Servidor falso: el refresh token vale UNA vez, como en el backend.
class _FakeServer implements HttpClientAdapter {
  _FakeServer(this.newAccess);

  final String newAccess;
  int refreshCalls = 0;
  final usedRefreshTokens = <String>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/api/v1/auth/refresh') {
      refreshCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final token = (options.data as Map)['refresh_token'] as String;
      if (!usedRefreshTokens.add(token)) return _json(401, {'error': 'revoked'});
      return _json(200, {'access_token': newAccess, 'refresh_token': 'refresh-2'});
    }
    if (options.headers['Authorization'] == 'Bearer $newAccess') {
      return _json(200, {'ok': true});
    }
    return _json(401, {'error': 'expired'});
  }

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  final expired = _jwt(DateTime.now().subtract(const Duration(minutes: 5)), 'old');
  final fresh = _jwt(DateTime.now().add(const Duration(minutes: 15)), 'new');

  test('dos 401 simultáneos comparten un solo refresh y no cierran la sesión', () async {
    final storage = _MemoryStorage(expired, 'refresh-1');
    final server = _FakeServer(fresh);
    var sessionExpired = false;
    final client = ApiClient(
      Dio()..httpClientAdapter = server,
      storage,
      onSessionExpired: () => sessionExpired = true,
    );

    final results = await Future.wait([
      client.dio.get<dynamic>('/api/v1/library'),
      client.dio.get<dynamic>('/api/v1/library'),
    ]);

    expect(results.map((r) => r.statusCode), [200, 200]);
    expect(server.refreshCalls, 1);
    expect(sessionExpired, isFalse);
    expect(storage.access, fresh);
  });

  test('freshAccessToken renueva un token caducado y respeta uno vigente', () async {
    final storage = _MemoryStorage(expired, 'refresh-1');
    final server = _FakeServer(fresh);
    final client = ApiClient(Dio()..httpClientAdapter = server, storage);

    expect(await client.freshAccessToken(), fresh);
    expect(server.refreshCalls, 1);

    // Ya vigente: se devuelve tal cual, sin otro refresh.
    expect(await client.freshAccessToken(), fresh);
    expect(server.refreshCalls, 1);
  });
}
