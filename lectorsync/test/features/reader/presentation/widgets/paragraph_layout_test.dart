import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Paragraph layout', () {
    testWidgets('first sentence has 24px indent via Row + SizedBox',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestParagraph(
              sentences: ['First sentence here.', 'Second sentence here.'],
            ),
          ),
        ),
      );

      final row = tester.widget<Row>(find.byType(Row));
      final sizedBox = row.children.first as SizedBox;
      expect(sizedBox.width, 24.0);

      final expanded = row.children.last as Expanded;
      expect(expanded.child, isA<Text>());

      final indentedText = expanded.child as Text;
      expect(indentedText.textAlign, TextAlign.justify);
    });

    testWidgets('non-first sentences are plain Text with justify',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestParagraph(
              sentences: ['First sentence.', 'Second sentence.', 'Third.'],
            ),
          ),
        ),
      );

      final texts = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(texts.length, 3);

      expect(texts[0].textAlign, TextAlign.justify);
      expect(texts[1].textAlign, TextAlign.justify);
      expect(texts[2].textAlign, TextAlign.justify);

      expect(find.byType(Row), findsOneWidget);
    });

    testWidgets('single sentence paragraph has indent',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestParagraph(
              sentences: ['Only one sentence.'],
            ),
          ),
        ),
      );

      expect(find.byType(Row), findsOneWidget);

      final row = tester.widget<Row>(find.byType(Row));
      final sizedBox = row.children.first as SizedBox;
      expect(sizedBox.width, 24.0);
    });

    testWidgets('empty sentences renders nothing', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: _TestParagraph(sentences: []),
          ),
        ),
      );

      expect(find.byType(Text), findsNothing);
      expect(find.byType(Row), findsNothing);
    });
  });
}

class _TestParagraph extends StatelessWidget {
  const _TestParagraph({required this.sentences});

  final List<String> sentences;

  @override
  Widget build(BuildContext context) {
    const indentWidth = 24.0;
    final style = Theme.of(context).textTheme.bodyLarge;

    if (sentences.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 0, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sentences.length; i++)
            i == 0
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const SizedBox(width: indentWidth),
                      Expanded(
                        child: Text(
                          sentences[i],
                          textAlign: TextAlign.justify,
                          style: style,
                        ),
                      ),
                    ],
                  )
                : Text(
                    sentences[i],
                    textAlign: TextAlign.justify,
                    style: style,
                  ),
        ],
      ),
    );
  }
}
