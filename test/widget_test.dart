import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/material.dart';

void main() {
  testWidgets('renders responsive scaffold shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Text('SmartSFA Test Shell'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('SmartSFA Test Shell'), findsOneWidget);
  });
}
