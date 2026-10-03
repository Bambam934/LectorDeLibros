import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'system_fullscreen.dart';

SystemFullscreen createPlatformFullscreen() => _WebFullscreen();

/// Fullscreen API del navegador.
///
/// Exige un gesto del usuario, y el botón del lector lo es. Safari en iPhone
/// no la implementa para elementos: ahí la petición falla y el modo se queda
/// en ocultar los controles del lector, que es lo único que puede hacer.
class _WebFullscreen implements SystemFullscreen {
  @override
  Future<void> init() async {}

  @override
  Future<void> enter() async {
    try {
      await web.document.documentElement?.requestFullscreen().toDart;
    } catch (_) {
      // Navegador sin soporte o sin gesto: se sigue sin pantalla completa.
    }
  }

  @override
  Future<void> exit() async {
    if (web.document.fullscreenElement == null) return;
    try {
      await web.document.exitFullscreen().toDart;
    } catch (_) {
      // Ya había salido (p. ej. con Esc del navegador).
    }
  }
}
