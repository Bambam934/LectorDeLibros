import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'system_fullscreen.dart';

SystemFullscreen createPlatformFullscreen() => _NativeFullscreen();

/// Móvil con `SystemChrome`; escritorio con `window_manager`.
///
/// La plataforma se decide con `defaultTargetPlatform` y no con
/// `Platform` de `dart:io`, igual que el resto del lector: en los tests
/// `Platform` es la máquina que los ejecuta, no la plataforma simulada.
class _NativeFullscreen implements SystemFullscreen {
  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // macOS y Linux se compilarían igual, pero el repo no tiene esas carpetas.
  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;

  @override
  Future<void> init() async {
    if (_isWindows) await windowManager.ensureInitialized();
  }

  @override
  Future<void> enter() async {
    if (_isMobile) {
      // `immersiveSticky`: las barras se ocultan, y un deslizamiento desde el
      // borde las asoma un momento sin sacarte del modo.
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else if (_isWindows) {
      await windowManager.setFullScreen(true);
    }
  }

  @override
  Future<void> exit() async {
    if (_isMobile) {
      // `manual` con todas las barras, y no `edgeToEdge`: con target 34 es lo
      // que devuelve la barra de estado y la de navegación a como estaban.
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } else if (_isWindows) {
      await windowManager.setFullScreen(false);
    }
  }
}
