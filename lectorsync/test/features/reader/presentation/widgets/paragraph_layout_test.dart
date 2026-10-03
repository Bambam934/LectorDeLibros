import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/presentation/reading_typography.dart';

/// Réplica del layout de un párrafo del lector.
///
/// `_ParagraphHighlightProxy` es privado y arrastra el BLoC entero, así que
/// aquí se reproduce su estructura. Para que la copia no se despegue del
/// original, **las medidas salen de `reading_typography.dart`**, que es de
/// donde las toma el widget de verdad: si alguien cambia la sangría, este
/// test la sigue.
class _TestParagraph extends StatelessWidget {
  const _TestParagraph({
    required this.sentences,
    this.fontSize = 18,
    this.isFirstParagraph = false,
    this.textAlign = TextAlign.left,
  });

  final List<String> sentences;
  final double fontSize;
  final bool isFirstParagraph;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final indent = paragraphIndent(
      fontSize: fontSize,
      isFirstParagraph: isFirstParagraph,
    );
    final style = TextStyle(fontSize: fontSize);

    if (sentences.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sentences.length; i++)
            i == 0 && indent > 0
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      SizedBox(width: indent),
                      Expanded(
                        child: Text(
                          sentences[i],
                          textAlign: textAlign,
                          style: style,
                        ),
                      ),
                    ],
                  )
                : Text(sentences[i], textAlign: textAlign, style: style),
        ],
      ),
    );
  }
}

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('Layout de párrafo', () {
    testWidgets('la primera oración se sangra con un Row + SizedBox',
        (tester) async {
      await _pump(
        tester,
        const _TestParagraph(
          sentences: ['Primera oración.', 'Segunda oración.'],
        ),
      );

      final row = tester.widget<Row>(find.byType(Row));
      final spacer = row.children.first as SizedBox;

      expect(spacer.width, paragraphIndent(fontSize: 18));
      expect(row.children.last, isA<Expanded>());
    });

    testWidgets('la sangría crece con el tamaño de letra', (tester) async {
      await _pump(
        tester,
        const _TestParagraph(sentences: ['Texto grande.'], fontSize: 32),
      );

      final row = tester.widget<Row>(find.byType(Row));
      final spacer = row.children.first as SizedBox;

      expect(spacer.width, paragraphIndent(fontSize: 32));
      expect(spacer.width, greaterThan(paragraphIndent(fontSize: 18)));
    });

    testWidgets('el primer párrafo del capítulo va sin Row de sangría',
        (tester) async {
      await _pump(
        tester,
        const _TestParagraph(
          sentences: ['Arranque del capítulo.', 'Sigue el texto.'],
          isFirstParagraph: true,
        ),
      );

      expect(find.byType(Row), findsNothing);
      expect(find.byType(Text), findsNWidgets(2));
    });

    testWidgets('todas las oraciones comparten la alineación elegida',
        (tester) async {
      await _pump(
        tester,
        const _TestParagraph(
          sentences: ['Una.', 'Dos.', 'Tres.'],
          textAlign: TextAlign.justify,
        ),
      );

      final texts = tester.widgetList<Text>(find.byType(Text)).toList();

      expect(texts.length, 3);
      for (final t in texts) {
        expect(t.textAlign, TextAlign.justify);
      }
    });

    testWidgets('sin oraciones no se pinta nada', (tester) async {
      await _pump(tester, const _TestParagraph(sentences: []));

      expect(find.byType(Text), findsNothing);
      expect(find.byType(Row), findsNothing);
    });
  });
}
