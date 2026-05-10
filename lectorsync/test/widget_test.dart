import 'package:flutter_test/flutter_test.dart';

import 'package:lectorsync/app.dart';
import 'package:lectorsync/core/di/injection_container.dart';

void main() {
  testWidgets('shows login as initial screen', (WidgetTester tester) async {
    await configureDependencies();
    await tester.pumpWidget(const LectorSyncApp());
    await tester.pumpAndSettle();

    expect(find.text('LectorSync'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
