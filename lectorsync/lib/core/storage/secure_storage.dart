import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStorage {
  SecureStorage(this._secureStorage);

  final FlutterSecureStorage _secureStorage;

  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';

  Future<void> saveTokens({required String access, required String refresh}) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_accessTokenKey, access);
        await prefs.setString(_refreshTokenKey, refresh);
      } else {
        await _secureStorage.write(key: _accessTokenKey, value: access);
        await _secureStorage.write(key: _refreshTokenKey, value: refresh);
      }
    } catch (e, st) {
      debugPrint('SecureStorage.saveTokens fallo: $e\n$st');
    }
  }

  Future<String?> getAccessToken() => _read(_accessTokenKey);

  Future<String?> getRefreshToken() => _read(_refreshTokenKey);

  Future<String?> _read(String key) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(key);
      }
      return await _secureStorage.read(key: key);
    } catch (e, st) {
      debugPrint('SecureStorage._read($key) fallo: $e\n$st');
      try {
        if (kIsWeb) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(key);
        } else {
          await _secureStorage.deleteAll();
        }
      } catch (_) {}
      return null;
    }
  }

  Future<void> clearTokens() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_accessTokenKey);
        await prefs.remove(_refreshTokenKey);
      } else {
        await _secureStorage.delete(key: _accessTokenKey);
        await _secureStorage.delete(key: _refreshTokenKey);
      }
    } catch (e) {
      debugPrint('SecureStorage.clearTokens fallo: $e');
      try {
        if (kIsWeb) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_accessTokenKey);
          await prefs.remove(_refreshTokenKey);
        } else {
          await _secureStorage.deleteAll();
        }
      } catch (_) {}
    }
  }
}
