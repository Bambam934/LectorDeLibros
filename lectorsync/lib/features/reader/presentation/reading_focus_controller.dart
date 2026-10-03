import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/focus/focus_prefs.dart';
import '../../../core/focus/quiet_mode.dart';
import '../../../core/focus/system_fullscreen.dart';

/// Respuesta del usuario cuando falta el "Acceso a No molestar".
enum QuietAccessChoice {
  /// Ir a Ajustes a concederlo.
  openSettings,

  /// Seguir sin silenciar y volver a preguntar la próxima vez.
  notNow,

  /// Seguir sin silenciar y no volver a preguntar.
  never,
}

/// Modo concentración del lector (ADR 12): pantalla completa y, donde la
/// plataforma lo permite, el "No molestar" del sistema.
///
/// Toda la lógica de estados vive aquí, fuera de `reader_page.dart`, para
/// poder probarla con dobles. La regla es una sola y se re-evalúa ante
/// cualquier cambio:
///
///     silencio = pantalla completa ∧ (app visible ∨ voz sonando)
///
/// siempre que la plataforma lo permita y haya acceso. El silencio sigue
/// mientras la voz lee con la pantalla apagada, porque eso también es estar
/// leyendo; se quita al pausar la voz en segundo plano, al salir de la
/// pantalla completa o al cerrar el libro.
///
/// Quitar el silencio nunca depende de que algo salga bien: el estado se
/// marca como apagado antes de pedírselo al sistema, y si activarlo falla se
/// considera apagado.
class ReadingFocusController extends ChangeNotifier {
  ReadingFocusController({
    required SystemFullscreen fullscreen,
    required QuietMode quietMode,
    required FocusPrefs prefs,
    required Future<QuietAccessChoice> Function() askForQuietAccess,
    Future<void> Function()? showDesktopQuietHint,
    this.voiceStopGrace = const Duration(seconds: 3),
  })  : _fullscreen = fullscreen,
        _quietMode = quietMode,
        _prefs = prefs,
        _askForQuietAccess = askForQuietAccess,
        _showDesktopQuietHint = showDesktopQuietHint;

  static const dontAskKey = 'quiet_access_dont_ask';
  static const desktopHintKey = 'desktop_quiet_hint_shown';

  final SystemFullscreen _fullscreen;
  final QuietMode _quietMode;
  final FocusPrefs _prefs;
  final Future<QuietAccessChoice> Function() _askForQuietAccess;
  final Future<void> Function()? _showDesktopQuietHint;

  /// Cuánto se espera, tras pararse la voz, antes de quitar el silencio con
  /// la app en segundo plano. Al pasar de capítulo la voz se para y vuelve a
  /// arrancar en menos de un segundo; sin este margen, el No molestar se
  /// quitaría y se pondría otra vez en cada cambio.
  final Duration voiceStopGrace;

  bool _isFullscreen = false;
  bool _visible = true;
  bool _voiceForQuiet = false;
  bool _quietOn = false;
  bool _disposed = false;
  Timer? _graceTimer;

  /// Cola que serializa las llamadas al sistema: activar y desactivar nunca
  /// se cruzan, y el último estado pedido es el que queda.
  Future<void> _queue = Future<void>.value();

  bool get isFullscreen => _isFullscreen;

  /// El "No molestar" del sistema está puesto por el lector.
  bool get isQuietOn => _quietOn;

  /// Termina cuando se han aplicado todos los cambios pendientes.
  @visibleForTesting
  Future<void> get settled => _queue;

  Future<void> enter() async {
    if (_isFullscreen || _disposed) return;
    _isFullscreen = true;
    _notify();
    await _guard(_fullscreen.enter);
    await _maybeAskForQuietAccess();
    await _maybeShowDesktopHint();
    await _sync();
  }

  Future<void> exit() async {
    if (!_isFullscreen) return;
    _isFullscreen = false;
    _notify();
    await _sync();
    await _guard(_fullscreen.exit);
  }

  Future<void> toggle() => _isFullscreen ? exit() : enter();

  /// La app pasa a primer plano (`true`) o a segundo plano (`false`).
  ///
  /// Al volver de Ajustes con el acceso recién concedido no hace falta nada
  /// más: la re-evaluación vuelve a preguntar si hay acceso y lo activa.
  Future<void> setAppVisible(bool visible) {
    if (_visible == visible) return _queue;
    _visible = visible;
    return _sync();
  }

  /// La voz empieza a sonar (`true`) o se para (`false`).
  Future<void> setVoicePlaying(bool playing) {
    if (playing) {
      _graceTimer?.cancel();
      _graceTimer = null;
      if (_voiceForQuiet) return _queue;
      _voiceForQuiet = true;
      return _sync();
    }
    if (!_voiceForQuiet || _graceTimer != null) return _queue;
    if (voiceStopGrace == Duration.zero) {
      _voiceForQuiet = false;
      return _sync();
    }
    _graceTimer = Timer(voiceStopGrace, () {
      _graceTimer = null;
      _voiceForQuiet = false;
      _sync();
    });
    return _queue;
  }

  /// Lo quita todo. Se llama al cerrar el libro.
  Future<void> shutdown() async {
    _graceTimer?.cancel();
    _graceTimer = null;
    _voiceForQuiet = false;
    if (_isFullscreen) {
      await exit();
    } else {
      await _sync();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(shutdown());
    super.dispose();
  }

  Future<void> _sync() {
    final next = _queue.then((_) => _apply());
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _apply() async {
    final want = _isFullscreen && (_visible || _voiceForQuiet);
    if (want && !_quietOn) {
      try {
        if (await _quietMode.isSupported() && await _quietMode.hasAccess()) {
          _quietOn = await _quietMode.activate();
        }
      } catch (e) {
        debugPrint('[ReadingFocus] no se pudo activar: $e');
        _quietOn = false;
      }
    } else if (!want && _quietOn) {
      _quietOn = false;
      try {
        await _quietMode.deactivate();
      } catch (e) {
        debugPrint('[ReadingFocus] no se pudo desactivar: $e');
      }
    }
    _notify();
  }

  Future<void> _maybeAskForQuietAccess() async {
    try {
      if (!await _quietMode.isSupported()) return;
      if (await _quietMode.hasAccess()) return;
      if (await _prefs.isSet(dontAskKey)) return;
    } catch (_) {
      return;
    }
    switch (await _askForQuietAccess()) {
      case QuietAccessChoice.openSettings:
        await _guard(_quietMode.openAccessSettings);
      case QuietAccessChoice.never:
        await _guard(() => _prefs.set(dontAskKey));
      case QuietAccessChoice.notNow:
        break;
    }
  }

  /// En escritorio no hay API para silenciar (ADR 12), pero Windows tiene su
  /// propia regla "No molestar en pantalla completa". Se avisa de ella una
  /// sola vez.
  Future<void> _maybeShowDesktopHint() async {
    final show = _showDesktopQuietHint;
    if (show == null) return;
    try {
      if (await _prefs.isSet(desktopHintKey)) return;
      await _prefs.set(desktopHintKey);
    } catch (_) {
      return;
    }
    await _guard(show);
  }

  Future<void> _guard(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      debugPrint('[ReadingFocus] $e');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
