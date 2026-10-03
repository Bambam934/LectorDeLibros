import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/tts/desktop_tts_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  late List<String> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return 1;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // En Windows, el `stop` nativo de flutter_tts 4.2.5 responde al `speak`
  // pendiente sin comprobar que exista: con `awaitSpeakCompletion(true)` y
  // ningún `speak` todavía, desreferencia un puntero nulo y la app se cierra.
  // El lector inicializa el motor al abrir el libro y para la voz al cerrarlo,
  // así que abrir un libro y volver atrás sin reproducir tumbaba la app.
  test('stop() antes del primer speak no llega al plugin', () async {
    final adapter = DesktopTtsAdapter();
    await adapter.stop();
    await adapter.dispose();

    expect(calls, isNot(contains('stop')));
  });

  test('después de hablar, stop() sí para el motor', () async {
    final adapter = DesktopTtsAdapter();
    await adapter.speak('hola');
    await adapter.stop();

    expect(calls, containsAllInOrder(['speak', 'stop']));
  });
}
