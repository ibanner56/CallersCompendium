import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/migration_guard.dart';
import 'package:compendium_app/src/widgets/app_bootstrap.dart';

void main() {
  testWidgets('shows a loading screen until the startup future completes', (
    tester,
  ) async {
    final completer = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: AppBootstrap(
          future: completer.future,
          onRetry: () {},
          builder: (_) => const Text('Collection ready'),
        ),
      ),
    );

    // Migration still running: loading, content gated.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Collection ready'), findsNothing);

    completer.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Collection ready'), findsOneWidget);
  });

  testWidgets('shows an error screen with retry when startup fails', (
    tester,
  ) async {
    var retried = false;
    final completer = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: AppBootstrap(
          future: completer.future,
          onRetry: () => retried = true,
          builder: (_) => const Text('Collection ready'),
        ),
      ),
    );

    completer.completeError(StateError('boom'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not prepare the collection'),
      findsOneWidget,
    );
    expect(find.text('Collection ready'), findsNothing);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('a downgrade error shows update guidance and no Retry', (
    tester,
  ) async {
    final completer = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: AppBootstrap(
          future: completer.future,
          onRetry: () {},
          builder: (_) => const Text('Collection ready'),
        ),
      ),
    );

    const error = DatabaseDowngradeError(fileVersion: 12, appVersion: 9);
    completer.completeError(error);
    await tester.pumpAndSettle();

    expect(find.text(error.message), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Collection ready'), findsNothing);
  });
}
