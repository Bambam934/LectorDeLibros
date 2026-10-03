import 'package:flutter/widgets.dart';

import 'app.dart';
import 'core/di/injection_container.dart';
import 'core/focus/system_fullscreen.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  // En Windows, window_manager tiene que inicializarse antes de runApp para
  // que la pantalla completa del lector funcione (ADR 12).
  await sl<SystemFullscreen>().init();
  runApp(const LectorSyncApp());
}
