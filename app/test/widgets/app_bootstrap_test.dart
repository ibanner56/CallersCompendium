import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/migration_guard.dart';
import 'package:compendium_app/src/widgets/app_bootstrap.dart';

import '../support/l10n_harness.dart';

/// No-op reset callbacks for tests that don't exercise the below-floor screen.
Future<void> _noopReset(DatabaseBelowFloorError _) async {}

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
          onBackUpAndReset: _noopReset,
          onResetOnly: _noopReset,
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
          onBackUpAndReset: _noopReset,
          onResetOnly: _noopReset,
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
          onBackUpAndReset: _noopReset,
          onResetOnly: _noopReset,
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

  testWidgets(
    'a below-floor error shows the recovery screen and no Retry (issue #841)',
    (tester) async {
      var backUpAndResetCalled = false;
      var resetOnlyCalled = false;
      final completer = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: AppBootstrap(
            future: completer.future,
            onRetry: () {},
            onBackUpAndReset: (_) async => backUpAndResetCalled = true,
            onResetOnly: (_) async => resetOnlyCalled = true,
            builder: (_) => const Text('Collection ready'),
          ),
        ),
      );

      const error = DatabaseBelowFloorError(
        fileVersion: 5,
        minSupportedVersion: 11,
        bridgeTag: 'v0.1.0-beta.6',
      );
      completer.completeError(error);
      await tester.pumpAndSettle();

      // Shows the headline — not the generic error.
      expect(
        find.text('This data is from a version too old to open'),
        findsOneWidget,
      );
      // Body mentions the bridge tag.
      expect(find.textContaining('v0.1.0-beta.6'), findsOneWidget);
      // The content is gated.
      expect(find.text('Collection ready'), findsNothing);
      // No Retry: retrying cannot apply retired migration steps.
      expect(find.text('Retry'), findsNothing);
      // Both reset buttons are present.
      expect(find.text('Back Up + Reset'), findsOneWidget);
      expect(find.text('Reset Only'), findsOneWidget);

      // Tapping Back Up + Reset fires the callback.
      await tester.tap(find.text('Back Up + Reset'));
      expect(backUpAndResetCalled, isTrue);
      expect(resetOnlyCalled, isFalse);
    },
  );

  testWidgets(
    'below-floor screen disables both buttons while a flow is in-flight '
    '(issue #841 — double-tap guard)',
    (tester) async {
      // A completer that lets us control when the action resolves, so we can
      // inspect button state mid-flight.
      final actionCompleter = Completer<void>();
      var callCount = 0;

      final bootstrapCompleter = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: AppBootstrap(
            future: bootstrapCompleter.future,
            onRetry: () {},
            onBackUpAndReset: (_) async {
              callCount++;
              await actionCompleter.future;
            },
            onResetOnly: _noopReset,
            builder: (_) => const Text('Collection ready'),
          ),
        ),
      );

      const error = DatabaseBelowFloorError(
        fileVersion: 5,
        minSupportedVersion: 11,
        bridgeTag: 'v0.1.0-beta.6',
      );
      bootstrapCompleter.completeError(error);
      await tester.pumpAndSettle();

      // Both buttons start enabled.
      final backUpButton = find.widgetWithText(FilledButton, 'Back Up + Reset');
      final resetButton = find.widgetWithText(OutlinedButton, 'Reset Only');
      expect(
        tester.widget<FilledButton>(backUpButton).onPressed,
        isNotNull,
        reason: 'Back Up + Reset should be enabled before any tap',
      );
      expect(
        tester.widget<OutlinedButton>(resetButton).onPressed,
        isNotNull,
        reason: 'Reset Only should be enabled before any tap',
      );

      // Tap — action is now in-flight (actionCompleter not yet resolved).
      await tester.tap(backUpButton);
      await tester.pump(); // let setState run
      expect(callCount, 1);

      // While in-flight both buttons must be disabled (onPressed == null).
      expect(
        tester.widget<FilledButton>(backUpButton).onPressed,
        isNull,
        reason: 'Back Up + Reset should be disabled while in-flight',
      );
      expect(
        tester.widget<OutlinedButton>(resetButton).onPressed,
        isNull,
        reason: 'Reset Only should be disabled while in-flight',
      );

      // A second tap while disabled must not fire the callback again.
      await tester.tap(backUpButton, warnIfMissed: false);
      await tester.pump();
      expect(callCount, 1, reason: 'second tap should be a no-op');

      // Resolve the action — buttons re-enable.
      actionCompleter.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(backUpButton).onPressed,
        isNotNull,
        reason: 'Back Up + Reset should be re-enabled after action completes',
      );
    },
  );

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
          onBackUpAndReset: _noopReset,
          onResetOnly: _noopReset,
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
          onBackUpAndReset: _noopReset,
          onResetOnly: _noopReset,
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
