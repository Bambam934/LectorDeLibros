import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// "No molestar" del sistema mientras se lee (ADR 12).
///
/// Solo Android tiene una API oficial para que una app lo active, y aun así a
/// través de una regla propia (`AutomaticZenRule`) que el usuario autoriza una
/// vez en Ajustes. En el resto de plataformas [isSupported] es `false` y el
/// modo concentración se queda en la pantalla completa.
abstract interface class QuietMode {
  /// La plataforma deja a la app silenciar el sistema (Android 10+).
  Future<bool> isSupported();

  /// El usuario concedió el "Acceso a No molestar".
  Future<bool> hasAccess();

  /// Abre la pantalla de Ajustes donde se concede el acceso.
  Future<void> openAccessSettings();

  /// Activa el silencio. `false` si no se pudo: sin permiso, Android antiguo
  /// o un error del sistema.
  Future<bool> activate();

  /// Quita el silencio. No lanza nunca: es la operación que tiene que salir
  /// bien siempre.
  Future<void> deactivate();
}

/// Implementación por canal nativo (`MainActivity.kt` y `ReadingQuietMode.kt`).
class ChannelQuietMode implements QuietMode {
  ChannelQuietMode([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel('lectorsync/quiet_mode');

  final MethodChannel _channel;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> isSupported() async => _isAndroid && await _call('isSupported');

  @override
  Future<bool> hasAccess() async => _isAndroid && await _call('hasAccess');

  @override
  Future<void> openAccessSettings() async {
    if (_isAndroid) await _call('openAccessSettings');
  }

  @override
  Future<bool> activate() async => _isAndroid && await _call('activate');

  @override
  Future<void> deactivate() async {
    if (_isAndroid) await _call('deactivate');
  }

  /// Un fallo del canal cuenta como "no". En el peor caso no se silencia, que
  /// es el lado seguro, y ninguna excepción llega hasta la interfaz.
  Future<bool> _call(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException catch (e) {
      debugPrint('[QuietMode] $method falló: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
