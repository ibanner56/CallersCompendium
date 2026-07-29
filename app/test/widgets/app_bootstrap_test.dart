import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/migration_guard.dart';
import 'package:compendium_app/src/widgets/app_bootstrap.dart';

import '../support/l10n_harness.dart';

void main() {
  testWidgets('shows a loading screen until the startup future completes', (
    tester,
  ) async {
    final completer = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
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
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
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
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
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

    expect(
      find.text(
        'This data was created by a newer version of Caller\u2019s Compendium '
        '\u2014 please update the app.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Collection ready'), findsNothing);
  });

  testWidgets('shows determinate rebuild progress when reported (#440)', (
    tester,
  ) async {
    final completer = Completer<void>();
    final progress = ValueNotifier<DerivedRebuildProgress?>(null);
    addTearDown(progress.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: AppBootstrap(
          future: completer.future,
          onRetry: () {},
          builder: (_) => const Text('Collection ready'),
          rebuildProgress: progress,
        ),
      ),
    );

    // No progress yet: plain indeterminate spinner (value == null).
    var indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, isNull);

    // Rebuild reports 1 of 4 dances done.
    progress.value = const DerivedRebuildProgress(completed: 1, total: 4);
    await tester.pump();

    indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, closeTo(0.25, 1e-9));
    expect(find.text('Rebuilding search index… 25%'), findsOneWidget);

    // Completing the future reveals the app.
    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('Collection ready'), findsOneWidget);
  });

  testWidgets('an empty-collection rebuild keeps the indeterminate spinner', (
    tester,
  ) async {
    final completer = Completer<void>();
    final progress = ValueNotifier<DerivedRebuildProgress?>(
      const DerivedRebuildProgress(completed: 0, total: 0),
    );
    addTearDown(progress.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: AppBootstrap(
          future: completer.future,
          onRetry: () {},
          builder: (_) => const Text('Collection ready'),
          rebuildProgress: progress,
        ),
      ),
    );

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, isNull);
    expect(find.textContaining('Rebuilding search index'), findsNothing);
  });
}
