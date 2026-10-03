import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/core/focus/focus_prefs.dart';
import 'package:lectorsync/core/focus/quiet_mode.dart';
import 'package:lectorsync/core/focus/system_fullscreen.dart';
import 'package:lectorsync/features/reader/presentation/reading_focus_controller.dart';

class _FakeFullscreen implements SystemFullscreen {
  int enters = 0;
  int exits = 0;
  bool throwOnEnter = false;

  @override
  Future<void> init() async {}

  @override
  Future<void> enter() async {
    enters++;
    if (throwOnEnter) throw StateError('sin ventana');
  }

  @override
  Future<void> exit() async => exits++;
}

class _FakeQuietMode implements QuietMode {
  bool supported = true;
  bool access = true;
  bool activateResult = true;
  bool throwOnActivate = false;
  bool throwOnDeactivate = false;
  int activations = 0;
  int deactivations = 0;
  int settingsOpened = 0;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> hasAccess() async => access;

  @override
  Future<void> openAccessSettings() async => settingsOpened++;

  @override
  Future<bool> activate() async {
    activations++;
    if (throwOnActivate) throw StateError('sistema');
    return activateResult;
  }

  @override
  Future<void> deactivate() async {
    deactivations++;
    if (throwOnDeactivate) throw StateError('sistema');
  }
}

class _FakePrefs implements FocusPrefs {
  final Set<String> flags = {};

  @override
  Future<bool> isSet(String key) async => flags.contains(key);

  @override
  Future<void> set(String key) async => flags.add(key);
}

void main() {
  late _FakeFullscreen fullscreen;
  late _FakeQuietMode quiet;
  late _FakePrefs prefs;
  late List<String> asked;
  late QuietAccessChoice nextChoice;
  late int hintsShown;

  ReadingFocusController build({
    bool desktopHint = false,
    Duration grace = Duration.zero,
  }) {
    return ReadingFocusController(
      fullscreen: fullscreen,
      quietMode: quiet,
      prefs: prefs,
      askForQuietAccess: () async {
        asked.add('access');
        return nextChoice;
      },
      showDesktopQuietHint: desktopHint ? () async => hintsShown++ : null,
      voiceStopGrace: grace,
    );
  }

  setUp(() {
    fullscreen = _FakeFullscreen();
    quiet = _FakeQuietMode();
    prefs = _FakePrefs();
    asked = [];
    nextChoice = QuietAccessChoice.notNow;
    hintsShown = 0;
  });

  group('entrar y salir', () {
    test('entrar pone la pantalla completa y el silencio', () async {
      final c = build();
      await c.enter();

      expect(c.isFullscreen, isTrue);
      expect(fullscreen.enters, 1);
      expect(c.isQuietOn, isTrue);
      expect(quiet.activations, 1);
    });

    test('salir quita el silencio y la pantalla completa', () async {
      final c = build();
      await c.enter();
      await c.exit();

      expect(c.isFullscreen, isFalse);
      expect(c.isQuietOn, isFalse);
      expect(quiet.deactivations, 1);
      expect(fullscreen.exits, 1);
    });

    test('sin soporte de la plataforma solo hay pantalla completa', () async {
      quiet.supported = false;
      final c = build();
      await c.enter();

      expect(c.isFullscreen, isTrue);
      expect(c.isQuietOn, isFalse);
      expect(quiet.activations, 0);
      expect(asked, isEmpty, reason: 'no se pide un permiso que no sirve');
    });

    test('un fallo de la pantalla completa no impide el resto', () async {
      fullscreen.throwOnEnter = true;
      final c = build();
      await c.enter();

      expect(c.isFullscreen, isTrue);
      expect(c.isQuietOn, isTrue);
    });
  });

  group('permiso de No molestar', () {
    test('sin acceso, pregunta y abre Ajustes si se pide', () async {
      quiet.access = false;
      nextChoice = QuietAccessChoice.openSettings;
      final c = build();
      await c.enter();

      expect(asked, ['access']);
      expect(quiet.settingsOpened, 1);
      expect(c.isQuietOn, isFalse);
    });

    test('al volver de Ajustes con el acceso concedido, silencia', () async {
      quiet.access = false;
      nextChoice = QuietAccessChoice.openSettings;
      final c = build();
      await c.enter();

      // Ajustes lleva la app a segundo plano y la devuelve.
      await c.setAppVisible(false);
      quiet.access = true;
      await c.setAppVisible(true);

      expect(c.isQuietOn, isTrue);
    });

    test('"no volver a preguntar" se respeta', () async {
      quiet.access = false;
      nextChoice = QuietAccessChoice.never;
      final c = build();
      await c.enter();
      await c.exit();
      await c.enter();

      expect(asked, ['access'], reason: 'solo la primera vez');
    });

    test('"ahora no" vuelve a preguntar la próxima vez', () async {
      quiet.access = false;
      nextChoice = QuietAccessChoice.notNow;
      final c = build();
      await c.enter();
      await c.exit();
      await c.enter();

      expect(asked, ['access', 'access']);
    });
  });

  group('segundo plano', () {
    test('sin voz, el silencio se quita al pasar a segundo plano', () async {
      final c = build();
      await c.enter();
      await c.setAppVisible(false);

      expect(c.isQuietOn, isFalse);
    });

    test('y vuelve al regresar a la app', () async {
      final c = build();
      await c.enter();
      await c.setAppVisible(false);
      await c.setAppVisible(true);

      expect(c.isQuietOn, isTrue);
    });

    test('con la voz sonando, el silencio sigue en segundo plano', () async {
      final c = build();
      await c.enter();
      await c.setVoicePlaying(true);
      await c.setAppVisible(false);

      expect(c.isQuietOn, isTrue);
    });

    test('al pararse la voz en segundo plano, el silencio se quita', () async {
      final c = build();
      await c.enter();
      await c.setVoicePlaying(true);
      await c.setAppVisible(false);
      await c.setVoicePlaying(false);
      await c.settled;

      expect(c.isQuietOn, isFalse);
    });

    test('un corte breve de la voz (cambio de capítulo) no lo quita',
        () async {
      final c = build(grace: const Duration(milliseconds: 80));
      await c.enter();
      await c.setVoicePlaying(true);
      await c.setAppVisible(false);

      await c.setVoicePlaying(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await c.setVoicePlaying(true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await c.settled;

      expect(c.isQuietOn, isTrue);
      expect(quiet.deactivations, 0);
    });

    test('pasado el margen, sí lo quita', () async {
      final c = build(grace: const Duration(milliseconds: 40));
      await c.enter();
      await c.setVoicePlaying(true);
      await c.setAppVisible(false);

      await c.setVoicePlaying(false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await c.settled;

      expect(c.isQuietOn, isFalse);
    });

    test('fuera de pantalla completa la voz no silencia nada', () async {
      final c = build();
      await c.setVoicePlaying(true);
      await c.setAppVisible(false);

      expect(c.isQuietOn, isFalse);
      expect(quiet.activations, 0);
    });
  });

  group('nunca se queda puesto', () {
    test('si activar falla, cuenta como apagado', () async {
      quiet.throwOnActivate = true;
      final c = build();
      await c.enter();

      expect(c.isQuietOn, isFalse);
    });

    test('si el sistema rechaza la activación, cuenta como apagado', () async {
      quiet.activateResult = false;
      final c = build();
      await c.enter();

      expect(c.isQuietOn, isFalse);
    });

    test('si desactivar falla, el estado queda apagado igual', () async {
      quiet.throwOnDeactivate = true;
      final c = build();
      await c.enter();
      await c.exit();

      expect(c.isQuietOn, isFalse);
    });

    test('cerrar el libro lo quita todo', () async {
      final c = build();
      await c.enter();
      await c.setVoicePlaying(true);
      await c.shutdown();

      expect(c.isQuietOn, isFalse);
      expect(c.isFullscreen, isFalse);
      expect(fullscreen.exits, 1);
    });

    test('dispose también lo quita', () async {
      final c = build();
      await c.enter();
      c.dispose();
      await Future<void>.delayed(Duration.zero);
      await c.settled;

      expect(quiet.deactivations, 1);
      expect(fullscreen.exits, 1);
    });
  });

  group('aviso de escritorio', () {
    test('se muestra una sola vez', () async {
      quiet.supported = false;
      final c = build(desktopHint: true);
      await c.enter();
      await c.exit();
      await c.enter();

      expect(hintsShown, 1);
    });
  });
}
