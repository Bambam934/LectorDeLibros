import 'system_fullscreen_stub.dart'
    if (dart.library.js_interop) 'system_fullscreen_web.dart'
    if (dart.library.io) 'system_fullscreen_native.dart';

/// Pantalla completa de verdad (ADR 12): oculta también las barras del
/// sistema en el móvil, el marco de la ventana en escritorio y la interfaz
/// del navegador en web.
///
/// Las implementaciones van detrás de importaciones condicionales, como en
/// `core/sync/sync_stream_client.dart`: la de web usa `package:web` y la
/// nativa `window_manager`, y ninguna de las dos compila en la otra
/// plataforma.
abstract interface class SystemFullscreen {
  /// Preparación de arranque. En Windows, `window_manager` exige inicializarse
  /// antes de `runApp`.
  Future<void> init();

  Future<void> enter();

  Future<void> exit();
}

SystemFullscreen createSystemFullscreen() => createPlatformFullscreen();
