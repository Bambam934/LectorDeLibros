/// Indicadores de espera con mensaje.
///
/// Un `CircularProgressIndicator` a secas dice "espera" pero no "a qué": el
/// usuario no distingue si la app está leyendo un índice o extrayendo el texto
/// de un PDF de 300 páginas, y una espera sin explicación se percibe como un
/// cuelgue. Estos widgets obligan a nombrar la operación.
library;

import 'package:flutter/material.dart';

/// Espera que ocupa toda el área disponible.
///
/// Para cuando no hay contenido que mostrar todavía: abrir un libro por
/// primera vez, cargar la biblioteca vacía.
class LoadingView extends StatelessWidget {
  const LoadingView({
    required this.message,
    this.detail,
    this.color,
    super.key,
  });

  /// Qué está pasando, en una línea. Ej.: "Preparando el libro".
  final String message;

  /// Contexto opcional: por qué tarda, o que solo ocurre una vez.
  final String? detail;

  /// Color del texto, para respetar la paleta de lectura.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurface;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: fg.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Capa translúcida sobre el contenido ya visible.
///
/// Para operaciones que ocurren *encima* de algo que ya se está viendo —
/// importar un libro con la biblioteca llena, borrar uno— donde sustituir la
/// pantalla entera por un spinner sería más desconcertante que informativo.
/// Bloquea la interacción a propósito: la operación va a recargar la lista y
/// tocar cosas mientras tanto deja la UI en un estado incoherente.
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({
    required this.visible,
    required this.child,
    this.message,
    this.detail,
    super.key,
  });

  final bool visible;
  final Widget child;
  final String? message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        child,
        if (visible)
          Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(
                color: scheme.surface.withValues(alpha: 0.85),
                child: LoadingView(
                  message: message ?? 'Un momento…',
                  detail: detail,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Indicador fino y discreto para esperas cortas sobre contenido legible.
///
/// Se usa al cambiar de capítulo: el texto anterior sigue en pantalla y
/// taparlo con un spinner a pantalla completa por medio segundo daría un
/// parpadeo peor que la propia espera.
class LoadingBar extends StatelessWidget {
  const LoadingBar({required this.visible, this.color, super.key});

  final bool visible;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox(height: 2);
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        minHeight: 2,
        backgroundColor: accent.withValues(alpha: 0.12),
        valueColor: AlwaysStoppedAnimation<Color>(accent),
      ),
    );
  }
}
