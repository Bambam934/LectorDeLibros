import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/core/widgets/loading_view.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  group('LoadingView', () {
    testWidgets('nombra la operación junto al indicador', (tester) async {
      await _pump(tester, const LoadingView(message: 'Preparando el libro'));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Preparando el libro'), findsOneWidget);
    });

    testWidgets('muestra el detalle cuando se le pasa', (tester) async {
      await _pump(
        tester,
        const LoadingView(
          message: 'Preparando el libro',
          detail: 'Solo pasa la primera vez.',
        ),
      );

      expect(find.text('Solo pasa la primera vez.'), findsOneWidget);
    });

    testWidgets('sin detalle solo pinta el mensaje', (tester) async {
      await _pump(tester, const LoadingView(message: 'Cargando'));

      expect(find.byType(Text), findsOneWidget);
    });
  });

  group('LoadingOverlay', () {
    testWidgets('deja ver el contenido cuando no hay nada en curso',
        (tester) async {
      await _pump(
        tester,
        const LoadingOverlay(
          visible: false,
          message: 'Importando',
          child: Text('Mi biblioteca'),
        ),
      );

      expect(find.text('Mi biblioteca'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('se superpone sin descartar el contenido', (tester) async {
      // Importante: la lista sigue en el árbol. Sustituirla por un spinner
      // perdería la posición de scroll al terminar.
      await _pump(
        tester,
        const LoadingOverlay(
          visible: true,
          message: 'Analizando libro.pdf',
          child: Text('Mi biblioteca'),
        ),
      );

      expect(find.text('Mi biblioteca'), findsOneWidget);
      expect(find.text('Analizando libro.pdf'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('bloquea la interacción mientras está visible',
        (tester) async {
      var taps = 0;
      await _pump(
        tester,
        LoadingOverlay(
          visible: true,
          message: 'Analizando',
          child: GestureDetector(
            onTap: () => taps++,
            child: const SizedBox.expand(child: Text('toca aquí')),
          ),
        ),
      );

      await tester.tap(find.text('toca aquí'), warnIfMissed: false);
      await tester.pump();

      expect(taps, 0, reason: 'el overlay debe absorber los toques');
    });
  });

  group('LoadingBar', () {
    testWidgets('aparece solo mientras dura la espera', (tester) async {
      await _pump(tester, const LoadingBar(visible: true));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await _pump(tester, const LoadingBar(visible: false));
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('ocupa el mismo alto visible o no', (tester) async {
      // Si el alto cambiase, el texto daría un salto al cargar el capítulo.
      await _pump(tester, const LoadingBar(visible: true));
      final shown = tester.getSize(find.byType(LoadingBar)).height;

      await _pump(tester, const LoadingBar(visible: false));
      final hidden = tester.getSize(find.byType(LoadingBar)).height;

      expect(shown, hidden);
    });
  });
}
