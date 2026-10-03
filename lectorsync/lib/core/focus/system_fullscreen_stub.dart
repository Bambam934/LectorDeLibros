import 'system_fullscreen.dart';

/// Plataformas sin web ni `dart:io`: no hay pantalla completa que pedir.
SystemFullscreen createPlatformFullscreen() => const _NoFullscreen();

class _NoFullscreen implements SystemFullscreen {
  const _NoFullscreen();

  @override
  Future<void> init() async {}

  @override
  Future<void> enter() async {}

  @override
  Future<void> exit() async {}
}
