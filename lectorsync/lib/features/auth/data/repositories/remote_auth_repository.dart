import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../domain/repositories/auth_repository.dart';

class RemoteAuthRepository implements AuthRepository {
  RemoteAuthRepository({
    required ApiClient apiClient,
    required SecureStorage secureStorage,
  })  : _dio = apiClient.dio,
        _storage = secureStorage;

  final Dio _dio;
  final SecureStorage _storage;

  @override
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/auth/login',
        data: {'email': email, 'password': password},
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        await _storage.saveTokens(
          access: data['access_token'] as String,
          refresh: data['refresh_token'] as String,
        );
        return true;
      }
      return false;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // Credenciales incorrectas — relanzar para que el Cubit muestre mensaje específico
        throw const AuthException('Correo o contraseña incorrectos.');
      }
      // Error de red u otro problema
      throw const AuthException('No se pudo conectar al servidor.');
    }
  }

  @override
  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/auth/register',
        data: {'name': name, 'email': email, 'password': password},
      );
      if (response.statusCode == 201) return true;
      return false;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        // Email ya registrado: intentar login automático con la contraseña dada
        return true;
      }
      throw const AuthException('No se pudo conectar al servidor.');
    }
  }

  Future<void> logout() async {
    try {
      final refreshToken = await _storage.getRefreshToken();
      await _dio.post('/api/v1/auth/logout', data: {
        if (refreshToken != null) 'refresh_token': refreshToken,
      });
    } catch (_) {
    } finally {
      await _storage.clearTokens();
    }
  }

  Future<bool> hasValidSession() async {
    return (await _storage.getAccessToken()) != null;
  }
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
}
