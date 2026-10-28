import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoge/runs/startup_retry_gate.dart';

void main() {
  testWidgets('startup retry gate triggers retry action once', (
    WidgetTester tester,
  ) async {
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StartupRetryGate(
          retryAction: () async {
            retryCount += 1;
          },
          child: const Text('ready'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(retryCount, 1);
    expect(find.text('ready'), findsOneWidget);
  });
}
