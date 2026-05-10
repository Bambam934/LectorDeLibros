import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditorialChapterHeader', () {
    testWidgets('renders chapter number, divider, and title',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: _TestEditorialHeader(
              chapterNumber: 1,
              chapterTitle: 'La Revolución',
            ),
          ),
        ),
      );

      expect(find.text('1'), findsOneWidget);
      expect(find.text('La Revolución'), findsOneWidget);
    });

    testWidgets('renders larger chapter number', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: _TestEditorialHeader(
              chapterNumber: 5,
              chapterTitle: 'Capítulo Cinco',
            ),
          ),
        ),
      );

      expect(find.text('5'), findsOneWidget);
      expect(find.text('Capítulo Cinco'), findsOneWidget);
    });
  });
}

class _TestEditorialHeader extends StatelessWidget {
  const _TestEditorialHeader({
    required this.chapterNumber,
    required this.chapterTitle,
  });

  final int chapterNumber;
  final String chapterTitle;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        children: [
          Text(
            '$chapterNumber',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: foreground,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 60,
            child: Divider(
              height: 1,
              thickness: 1,
              color: foreground.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            chapterTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: foreground.withValues(alpha: 0.9),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
