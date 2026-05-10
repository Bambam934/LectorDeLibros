import 'package:flutter/widgets.dart';

import 'app.dart';
import 'core/di/injection_container.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  runApp(const LectorSyncApp());
}
