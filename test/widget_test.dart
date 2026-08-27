import 'package:flutter_test/flutter_test.dart';

import 'package:storev2/main.dart';

void main() {
  testWidgets('App boots and shows the bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const RestockApp());
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('POS'), findsOneWidget);
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Restock'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });
}
