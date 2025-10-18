import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders greeting text', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Hello Sky'))),
    );

    expect(find.text('Hello Sky'), findsOneWidget);
  });
}
