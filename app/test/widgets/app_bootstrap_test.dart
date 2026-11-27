import 'dart:async';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/migration_guard.dart';
import 'package:compendium_app/src/update/retirement_banner.dart'
    show kReleasesPageUrl;
import 'package:compendium_app/src/widgets/app_bootstrap.dart';
import 'package:compendium_app/src/widgets/brand_mark.dart';

import '../support/fake_url_launcher.dart';
import '../support/l10n_harness.dart';

/// No-op reset callbacks for tests that don't exercise the below-floor screen.
Future<void> _noopReset(DatabaseBelowFloorError _) async {}

/// No-op share callback for tests that don't exercise the share action.
Future<void> _noopShare(DatabaseBelowFloorError _, Rect? _) async {}

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
          onShareRecoveryCopy: _noopShare,
          builder: (_) => const Text('Collection ready'),
        ),
      ),
    );

    // Migration still running: loading, content gated.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(BrandMark), findsOneWidget);
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
          onShareRecoveryCopy: _noopShare,
          builder: (_) => const Text('Collection ready'),
        ),
      ),
    );

    completer.completeError(StateError('boom'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Couldn't prepare your library"),
      findsOneWidget,
    );
    expect(find.text('Collection ready'), findsNothing);
    // The brand mark replaces the generic Material error glyph.
    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);

    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('Copy details scrubs the stack the way CrashFallback does', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
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
          onShareRecoveryCopy: _noopShare,
          builder: (_) => const Text('Collection ready'),
        ),
      ),
    );

    completer.completeError(
      StateError('boom'),
      StackTrace.fromString(
        '#0      Db.open (file:///home/jane.doe/src/app/lib/db.dart:12:3)\n'
        '#1      main (package:compendium_app/main.dart:4:1)\n',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bootstrap-copy-details')));
    await tester.pumpAndSettle();

    expect(clipboardText, isNotNull);
    expect(clipboardText, contains('StateError'));
    expect(clipboardText, contains('Db.open'));
    expect(clipboardText, contains('package:compendium_app/main.dart'));
    expect(clipboardText, isNot(contains('jane.doe')));
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
          onShareRecoveryCopy: _noopShare,
          builder: (_) => const Text('Collection ready'),
        ),
      ),
    );

    const error = DatabaseDowngradeError(fileVersion: 12, appVersion: 9);
    completer.completeError(error);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This data was created by a newer version of Caller\'s Compendium. '
        'Update the app, then reopen it.',
      ),
      findsOneWidget,
    );
    // Both versions are shown, so the caller can see how far behind the app is.
    expect(
      find.text(
        'Your data uses storage format 12. This version of the app reads up '
        'to format 9.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsNothing);
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
            onShareRecoveryCopy: _noopShare,
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
      expect(find.textContaining('Install v0.1.0-beta.6'), findsOneWidget);
      // Recovering the data is the primary action: a filled button naming
      // the bridge build.
      final getBridge = find.byKey(const ValueKey('bootstrap-get-bridge'));
      expect(getBridge, findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Get v0.1.0-beta.6'),
          matching: find.bySubtype<FilledButton>(),
        ),
        findsOneWidget,
      );
      // The two resets abandon the data, so they are outlined buttons under
      // their own 'Start fresh instead' label, below the primary action.
      final startFresh = find.text('Start fresh instead');
      expect(startFresh, findsOneWidget);
      for (final label in ['Back up + reset', 'Reset only']) {
        final button = find.widgetWithText(OutlinedButton, label);
        expect(button, findsOneWidget, reason: label);
        expect(
          tester.getTopLeft(button).dy,
          greaterThan(tester.getBottomLeft(startFresh).dy),
          reason: '$label sits under Start fresh instead',
        );
      }
      expect(
        tester.getTopLeft(startFresh).dy,
        greaterThan(tester.getBottomLeft(getBridge).dy),
      );
      // The content is gated.
      expect(find.text('Collection ready'), findsNothing);
      // No Retry: retrying cannot apply retired migration steps.
      expect(find.text('Try again'), findsNothing);
      // Both reset buttons are present.
      expect(find.text('Back up + reset'), findsOneWidget);
      expect(find.text('Reset only'), findsOneWidget);

      // Tapping Back up + reset fires the callback.
      await tester.tap(find.text('Back up + reset'));
      expect(backUpAndResetCalled, isTrue);
      expect(resetOnlyCalled, isFalse);
    },
    // The install-the-bridge route is the desktop one; Android and iOS have
    // their own wording (pre-release audit finding F-01), tested below.
    variant: TargetPlatformVariant.desktop(),
  );

  group('below floor: each platform is given a route that keeps the data', () {
    // A database at schema v39 (v0.7.x), the case the floor raise to 40 sends
    // here. The bridge's tag and the version TestFlight shows for it differ.
    const error = DatabaseBelowFloorError(
      fileVersion: 39,
      minSupportedVersion: 40,
      bridgeTag: 'v0.10.0-beta',
    );

    Future<FakeUrlLauncher> pumpBelowFloor(
      WidgetTester tester, {
      List<Rect?>? shares,
    }) async {
      final launcher = installFakeUrlLauncher();
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
            onShareRecoveryCopy: (e, origin) async {
              expect(e, same(error));
              shares?.add(origin);
            },
            builder: (_) => const Text('Collection ready'),
          ),
        ),
      );
      completer.completeError(error);
      await tester.pumpAndSettle();
      return launcher;
    }

    // Read the strings through the screen's own localizations, so the tests
    // hold in whatever locale the test host resolves.
    AppLocalizations l10nOf(WidgetTester tester) =>
        AppLocalizations.of(tester.element(find.byType(Scaffold)));

    void expectResetsAndCopyDetailsKept() {
      expect(
        find.byKey(const ValueKey('bootstrap-back-up-and-reset')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('bootstrap-reset-only')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('bootstrap-copy-details')),
        findsOneWidget,
      );
    }

    /// On Android, iPhone and iPad: the only filled (primary) action shares a
    /// scrubbed copy, handing the share sheet the button's rectangle, and the
    /// link under it opens the user guide's computer route. Nothing opens the
    /// release page.
    Future<void> expectShareAndGuideNotReleasePage(
      WidgetTester tester,
      FakeUrlLauncher launcher,
      List<Rect?> shares,
    ) async {
      final l10n = l10nOf(tester);
      expect(find.byKey(const ValueKey('bootstrap-get-bridge')), findsNothing);
      expect(
        find.text(l10n.migrationBelowFloorGetBridge('v0.10.0-beta')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('bootstrap-releases-link')),
        findsNothing,
      );
      final share = find.byKey(const ValueKey('bootstrap-share-recovery-copy'));
      expect(find.bySubtype<FilledButton>(), findsOneWidget);
      expect(tester.widget(share), isA<FilledButton>());
      expect(
        find.descendant(
          of: share,
          matching: find.text(l10n.migrationBelowFloorShareCopy),
        ),
        findsOneWidget,
      );

      await tester.tap(share);
      await tester.pumpAndSettle();
      expect(shares, hasLength(1));
      expect(shares.single, tester.getRect(share));

      final guide = find.byKey(const ValueKey('bootstrap-recovery-guide'));
      expect(
        find.descendant(
          of: guide,
          matching: find.text(l10n.migrationBelowFloorComputerGuide),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(guide);
      await tester.tap(guide);
      await tester.pumpAndSettle();
      expect(launcher.launchedUrls, [kBelowFloorRecoveryGuideUrl]);
      expect(
        launcher.launchedUrls.where((u) => u.startsWith(kReleasesPageUrl)),
        isEmpty,
      );
    }

    testWidgets(
      'desktop: install the bridge, open it once, install this version again',
      (tester) async {
        final launcher = await pumpBelowFloor(tester);
        final l10n = l10nOf(tester);
        expect(
          find.text(l10n.migrationBelowFloorBody('v0.10.0-beta')),
          findsOneWidget,
        );
        final getBridge = find.byKey(const ValueKey('bootstrap-get-bridge'));
        expect(tester.widget(getBridge), isA<FilledButton>());
        // Desktop callers can reach their data folder; no share action.
        expect(
          find.byKey(const ValueKey('bootstrap-share-recovery-copy')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('bootstrap-recovery-guide')),
          findsNothing,
        );
        await tester.tap(getBridge);
        await tester.pumpAndSettle();
        expect(launcher.launchedUrls, ['$kReleasesPageUrl/tag/v0.10.0-beta']);
        expectResetsAndCopyDetailsKept();
      },
      variant: TargetPlatformVariant.desktop(),
    );

    testWidgets(
      'Android: says not to uninstall, and the primary action shares a copy '
      'instead of sending the caller to the release page',
      (tester) async {
        final shares = <Rect?>[];
        final launcher = await pumpBelowFloor(tester, shares: shares);
        final l10n = l10nOf(tester);
        expect(
          find.text(l10n.migrationBelowFloorBodyAndroid('v0.10.0-beta')),
          findsOneWidget,
        );
        expect(
          find.text(l10n.migrationBelowFloorBody('v0.10.0-beta')),
          findsNothing,
        );
        // Android will not install the older bridge over this version, and
        // uninstalling to make room deletes the library: no button offers it.
        await expectShareAndGuideNotReleasePage(tester, launcher, shares);
        expectResetsAndCopyDetailsKept();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'iPhone and iPad: points to TestFlight previous builds and offers the '
      'same share, not the release page',
      (tester) async {
        final shares = <Rect?>[];
        final launcher = await pumpBelowFloor(tester, shares: shares);
        final l10n = l10nOf(tester);
        // TestFlight lists the bridge by its version number, not its tag.
        expect(
          find.text(l10n.migrationBelowFloorBodyIos('0.10.0')),
          findsOneWidget,
        );
        expect(
          find.text(l10n.migrationBelowFloorBody('v0.10.0-beta')),
          findsNothing,
        );
        // The release page has no iOS download.
        await expectShareAndGuideNotReleasePage(tester, launcher, shares);
        expectResetsAndCopyDetailsKept();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    test('the guide link points at a heading the user guide has', () {
      final anchor = Uri.parse(kBelowFloorRecoveryGuideUrl).fragment;
      expect(anchor, isNotEmpty);
      expect(
        kBelowFloorRecoveryGuideUrl,
        startsWith(
          'https://github.com/ibanner56/CallersCompendium/blob/main/'
          'docs/user/faq.md#',
        ),
      );
      // GitHub's anchor for a heading: lower case, punctuation other than
      // hyphens dropped, spaces turned into hyphens.
      String anchorOf(String heading) => heading
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\- ]', unicode: true), '')
          .replaceAll(' ', '-');
      final headings = [
        for (final line in File('assets/docs/user/faq.md').readAsLinesSync())
          if (line.startsWith('#')) line.replaceFirst(RegExp(r'^#+\s*'), ''),
      ];
      expect(headings.map(anchorOf), contains(anchor));
    });
  });

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
            onShareRecoveryCopy: _noopShare,
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
      final backUpButton = find.widgetWithText(
        OutlinedButton,
        'Back up + reset',
      );
      final resetButton = find.widgetWithText(OutlinedButton, 'Reset only');
      expect(
        tester.widget<OutlinedButton>(backUpButton).onPressed,
        isNotNull,
        reason: 'Back up + reset should be enabled before any tap',
      );
      expect(
        tester.widget<OutlinedButton>(resetButton).onPressed,
        isNotNull,
        reason: 'Reset only should be enabled before any tap',
      );

      // Tap — action is now in-flight (actionCompleter not yet resolved).
      await tester.tap(backUpButton);
      await tester.pump(); // let setState run
      expect(callCount, 1);

      // While in-flight both buttons must be disabled (onPressed == null).
      expect(
        tester.widget<OutlinedButton>(backUpButton).onPressed,
        isNull,
        reason: 'Back up + reset should be disabled while in-flight',
      );
      expect(
        tester.widget<OutlinedButton>(resetButton).onPressed,
        isNull,
        reason: 'Reset only should be disabled while in-flight',
      );

      // A second tap while disabled must not fire the callback again.
      await tester.tap(backUpButton, warnIfMissed: false);
      await tester.pump();
      expect(callCount, 1, reason: 'second tap should be a no-op');

      // Resolve the action — buttons re-enable.
      actionCompleter.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<OutlinedButton>(backUpButton).onPressed,
        isNotNull,
        reason: 'Back up + reset should be re-enabled after action completes',
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
          onShareRecoveryCopy: _noopShare,
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

    // The determinate branch keeps the brand mark too.
    expect(find.byType(BrandMark), findsOneWidget);

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
          onShareRecoveryCopy: _noopShare,
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

  group('every terminal startup screen offers a way to report and get help', () {
    final stack = StackTrace.fromString(
      '#0      Db.open (file:///home/jane.doe/src/app/lib/db.dart:12:3)\n',
    );
    final cases = <String, ({Object error, List<String> detailLines})>{
      'downgrade': (
        error: const DatabaseDowngradeError(fileVersion: 12, appVersion: 9),
        detailLines: [
          'DatabaseDowngradeError',
          'fileVersion: 12',
          'appVersion: 9',
        ],
      ),
      'below floor': (
        error: const DatabaseBelowFloorError(
          fileVersion: 5,
          minSupportedVersion: 11,
          bridgeTag: 'v0.1.0-beta.6',
        ),
        detailLines: [
          'DatabaseBelowFloorError',
          'fileVersion: 5',
          'minSupportedVersion: 11',
          'bridgeTag: v0.1.0-beta.6',
        ],
      ),
      'snapshot aborted': (
        error: MigrationSnapshotAborted(
          SnapshotFailure(
            fromVersion: 9,
            toVersion: 12,
            cause: SnapshotFailureCause.diskFull,
            error: const FileSystemException(
              'No space left on device',
              '/home/jane.doe/backups',
            ),
          ),
        ),
        detailLines: [
          'MigrationSnapshotAborted',
          'cause: diskFull',
          'fromVersion: 9',
          'toVersion: 12',
        ],
      ),
      'snapshot aborted, database in use': (
        error: MigrationSnapshotAborted(
          SnapshotFailure(
            fromVersion: 12,
            toVersion: 12,
            cause: SnapshotFailureCause.databaseInUse,
            error: const SnapshotDatabaseInUse('/home/jane.doe/compendium'),
          ),
        ),
        detailLines: [
          'MigrationSnapshotAborted',
          'cause: databaseInUse',
          'fromVersion: 12',
          'toVersion: 12',
        ],
      ),
      'relocation blocked': (
        error: DatabaseRelocationBlocked(
          DatabaseRelocationFailure.bothExist,
          error: const FileSystemException('x', '/home/jane.doe/Documents'),
          copies: [
            DatabaseCopy(
              location: DatabaseCopyLocation.documents,
              bytes: 4096,
              modified: DateTime(2026, 10, 6, 15, 14),
            ),
          ],
        ),
        detailLines: [
          'DatabaseRelocationBlocked',
          'reason: bothExist',
          'copy: documents, 4096 bytes',
        ],
      ),
    };

    for (final entry in cases.entries) {
      testWidgets(
        '${entry.key}: Copy details, Releases link, no retry',
        (tester) async {
          String? clipboardText;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboardText = (call.arguments as Map)['text'] as String?;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          final launcher = installFakeUrlLauncher();
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
                onShareRecoveryCopy: _noopShare,
                builder: (_) => const Text('Collection ready'),
              ),
            ),
          );
          completer.completeError(entry.value.error, stack);
          await tester.pumpAndSettle();

          // R2-check-again: terminal means terminal, whatever could clear.
          expect(find.text('Try again'), findsNothing);
          expect(find.textContaining('Check again'), findsNothing);
          expect(find.text('Collection ready'), findsNothing);

          await tester.tap(
            find.byKey(const ValueKey('bootstrap-copy-details')),
          );
          await tester.pumpAndSettle();
          expect(clipboardText, isNotNull);
          for (final line in entry.value.detailLines) {
            expect(clipboardText, contains(line));
          }
          expect(clipboardText, contains('Db.open'));
          // Neither the stack's home directory nor the error's own message (which
          // can carry a path) reaches the clipboard.
          expect(clipboardText, isNot(contains('jane.doe')));
          expect(clipboardText, isNot(contains('No space left')));

          if (entry.key == 'below floor') {
            // Its way to help is the primary Get button, which opens the bridge
            // build's release; the generic Releases link is not shown here.
            expect(
              find.byKey(const ValueKey('bootstrap-releases-link')),
              findsNothing,
            );
            await tester.ensureVisible(
              find.byKey(const ValueKey('bootstrap-get-bridge')),
            );
            await tester.tap(
              find.byKey(const ValueKey('bootstrap-get-bridge')),
            );
            await tester.pumpAndSettle();
            expect(launcher.launchedUrls, [
              '$kReleasesPageUrl/tag/v0.1.0-beta.6',
            ]);
          } else {
            await tester.ensureVisible(
              find.byKey(const ValueKey('bootstrap-releases-link')),
            );
            await tester.tap(
              find.byKey(const ValueKey('bootstrap-releases-link')),
            );
            await tester.pumpAndSettle();
            expect(launcher.launchedUrls, [kReleasesPageUrl]);
          }
          // Only the desktop below-floor screen has a Get button; the Android
          // and iOS ones are tested in their own group above.
        },
        variant: entry.key == 'below floor'
            ? TargetPlatformVariant.desktop()
            : const DefaultTestVariant(),
      );
    }

    testWidgets('below floor keeps both reset actions beside the new ones', (
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
            onShareRecoveryCopy: _noopShare,
            builder: (_) => const Text('Collection ready'),
          ),
        ),
      );
      completer.completeError(cases['below floor']!.error);
      await tester.pumpAndSettle();
      expect(find.text('Back up + reset'), findsOneWidget);
      expect(find.text('Reset only'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('bootstrap-copy-details')),
        findsOneWidget,
      );
    });

    testWidgets('the screens say a restart is needed after the fix', (
      tester,
    ) async {
      // R2-check-again: with no Check again, the copy is what tells the caller
      // the app has to be reopened.
      for (final name in [
        'downgrade',
        'snapshot aborted',
        'relocation blocked',
      ]) {
        final completer = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: AppBootstrap(
              future: completer.future,
              onRetry: () {},
              onBackUpAndReset: _noopReset,
              onResetOnly: _noopReset,
              onShareRecoveryCopy: _noopShare,
              builder: (_) => const Text('Collection ready'),
            ),
          ),
        );
        completer.completeError(cases[name]!.error);
        await tester.pumpAndSettle();
        expect(find.textContaining('reopen'), findsWidgets, reason: name);
      }
    });
  });
}
