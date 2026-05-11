import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../storage/secure_storage.dart';

typedef OnSessionExpired = void Function();

class ApiClient {
  ApiClient(this._dio, this._secureStorage, {OnSessionExpired? onSessionExpired})
      : _onSessionExpired = onSessionExpired {
    _dio.options.baseUrl = _getBaseUrl();
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (!options.headers.containsKey('Authorization')) {
            final token = await _secureStorage.getAccessToken();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            final requestOptions = error.requestOptions;
            final isLoginRequest = requestOptions.path == '/api/v1/auth/login';
            final isRefreshRequest = requestOptions.path == '/api/v1/auth/refresh';
            if (isLoginRequest || isRefreshRequest) {
              return handler.next(error);
            }
            final refreshed = await _tryRefreshToken();
            if (refreshed) {
              final newToken = await _secureStorage.getAccessToken();
              if (newToken != null) {
                requestOptions.headers['Authorization'] = 'Bearer $newToken';
                try {
                  final response = await _dio.fetch(requestOptions);
                  return handler.resolve(response);
                } catch (_) {
                  return handler.next(error);
                }
              }
            }
            await _secureStorage.clearTokens();
            _onSessionExpired?.call();
          }
          return handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final SecureStorage _secureStorage;
  final OnSessionExpired? _onSessionExpired;

  Dio get dio => _dio;

  String _getBaseUrl() {
    const envBaseUrl = String.fromEnvironment('API_BASE_URL');
    if (envBaseUrl.isNotEmpty) return envBaseUrl;
    if (kIsWeb) return 'http://localhost:3000';
    if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://localhost:3000';
  }

  Future<bool> _tryRefreshToken() async {
    final refreshToken = await _secureStorage.getRefreshToken();
    if (refreshToken == null) return false;
    try {
      final response = await _dio.post(
        '/api/v1/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(headers: {'Authorization': ''}),
      );
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        await _secureStorage.saveTokens(
          access: data['access_token'] as String,
          refresh: data['refresh_token'] as String,
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
