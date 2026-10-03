import 'package:shared_preferences/shared_preferences.dart';

/// Marcas persistentes del modo concentración ("ya se avisó", "no volver a
/// preguntar"). Interfaz mínima para poder sustituirla en los tests.
abstract interface class FocusPrefs {
  Future<bool> isSet(String key);

  Future<void> set(String key);
}

class SharedFocusPrefs implements FocusPrefs {
  static const _prefix = 'reading_focus_';

  @override
  Future<bool> isSet(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$key') ?? false;
  }

  @override
  Future<void> set(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$key', true);
  }
}
