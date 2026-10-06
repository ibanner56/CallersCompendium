import 'dart:convert';

import 'package:compendium_app/src/update/retirement_banner.dart';
import 'package:compendium_app/src/update/semver.dart';
import 'package:compendium_app/src/update/update_config.dart';
import 'package:compendium_app/src/update/update_controller.dart';
import 'package:compendium_app/src/update/update_manifest.dart';
import 'package:compendium_app/src/update/update_scope.dart';
import 'package:compendium_app/src/update/update_service.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_url_launcher.dart';
import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// A stable manifest for [version] carrying [retirements] (a JSON list
/// literal), or no `retirements` field at all when it is `null`.
String _manifest(String version, {String? retirements}) =>
    '''
{
  "manifestSchemaVersion": 1,
  "channel": "stable",
  "version": "$version",
  "releaseNotesUrl": "https://github.com/ibanner56/CallersCompendium/releases/tag/v$version",
  "pubDate": "2026-08-01T00:00:00Z",
  ${retirements == null ? '' : '"retirements": $retirements,'}
  "artifacts": [
    {"platform": "linux", "arch": "x64", "url": "https://example.com/a", "sha256": "x", "size": 1}
  ]
}
''';

const _retire070 = '[{"through": "0.7.0", "endOfLife": "2027-01-31"}]';

/// A controller for build [current] whose fetch serves whatever [body] holds
/// (`null` = offline), on a clock fixed at [now].
UpdateController _controller(
  CompendiumRepositories repos,
  ValueNotifier<String?> body, {
  String current = '0.7.0',
  DateTime? now,
}) {
  return UpdateController(
    repos.settings,
    service: UpdateService(
      fetcher: (channel, {http.Client? client}) async =>
          body.value == null ? null : utf8.encode(body.value!),
      signatureFetcher: (channel, {http.Client? client}) async => 'sig',
      signatureVerifier: (bytes, sig) async => true,
    ),
    currentVersion: SemVer.tryParse(current),
    platform: UpdatePlatform.linux,
    arch: UpdateArch.x64,
    clock: () => now ?? DateTime(2026, 10, 6, 12),
  );
}

void main() {
  group('UpdateController — retirement notice', () {
    test('a check that finds an end-of-life date for this build surfaces '
        'and caches it', () async {
      final repos = openTestRepositories();
      final body = ValueNotifier<String?>(
        _manifest('0.8.0', retirements: _retire070),
      );
      final controller = _controller(repos, body);
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.retirementNotice, isNull);

      await controller.checkNow();

      expect(controller.retirementNotice?.endOfLife, DateTime.utc(2027, 1, 31));
      expect(controller.retirementNotice?.isPast, isFalse);
      expect(controller.retirementBanner, isNotNull);
      expect(await repos.settings.get(kUpdateRetirementNoticeKey), {
        'build': '0.7.0',
        'endOfLife': '2027-01-31',
      });
    });

    test('the cached notice is restored on the next launch, offline', () async {
      final repos = openTestRepositories();
      final body = ValueNotifier<String?>(
        _manifest('0.8.0', retirements: _retire070),
      );
      final first = _controller(repos, body);
      addTearDown(first.dispose);
      await first.load();
      await first.checkNow();

      body.value = null; // offline from here on
      final relaunched = _controller(repos, body);
      addTearDown(relaunched.dispose);
      await relaunched.load();

      expect(relaunched.retirementNotice?.endOfLife, DateTime.utc(2027, 1, 31));
      // A failed check is not evidence that the notice was withdrawn.
      await relaunched.checkNow();
      expect(relaunched.retirementNotice, isNotNull);
    });

    test('an authenticated manifest that no longer announces it clears '
        'the notice', () async {
      final repos = openTestRepositories();
      final body = ValueNotifier<String?>(
        _manifest('0.8.0', retirements: _retire070),
      );
      final controller = _controller(repos, body);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.checkNow();
      expect(controller.retirementNotice, isNotNull);

      body.value = _manifest('0.8.0');
      await controller.checkNow();

      expect(controller.retirementNotice, isNull);
      expect(
        await repos.settings.contains(kUpdateRetirementNoticeKey),
        isFalse,
      );
    });

    test('a notice cached by another build is ignored and dropped', () async {
      final repos = openTestRepositories();
      await repos.settings.set(kUpdateRetirementNoticeKey, {
        'build': '0.6.1',
        'endOfLife': '2027-01-31',
      });
      final controller = _controller(repos, ValueNotifier<String?>(null));
      addTearDown(controller.dispose);
      await controller.load();

      expect(controller.retirementNotice, isNull);
      expect(
        await repos.settings.contains(kUpdateRetirementNoticeKey),
        isFalse,
      );
    });

    test('a build with nothing newer in its channel is still warned', () async {
      // A beta build on the stable channel: stable.json is older, so there is
      // no update to offer, but the retirement still applies to this build.
      final repos = openTestRepositories();
      final body = ValueNotifier<String?>(
        _manifest('0.6.0', retirements: _retire070),
      );
      final controller = _controller(repos, body, current: '0.7.0-beta');
      addTearDown(controller.dispose);
      await controller.load();
      await controller.checkNow();

      expect(controller.foundUpdate, isNull);
      expect(controller.status, UpdateCheckStatus.noUpdate);
      expect(controller.retirementNotice?.endOfLife, DateTime.utc(2027, 1, 31));
    });

    test('a newer build is not warned', () async {
      final repos = openTestRepositories();
      final body = ValueNotifier<String?>(
        _manifest('0.8.0', retirements: _retire070),
      );
      final controller = _controller(repos, body, current: '0.7.1');
      addTearDown(controller.dispose);
      await controller.load();
      await controller.checkNow();

      expect(controller.retirementNotice, isNull);
    });

    test(
      'the notice turns into a lapse on the end-of-life day itself',
      () async {
        final repos = openTestRepositories();
        final body = ValueNotifier<String?>(
          _manifest('0.8.0', retirements: _retire070),
        );
        final eve = _controller(
          repos,
          body,
          now: DateTime(2027, 1, 30, 23, 59),
        );
        addTearDown(eve.dispose);
        await eve.load();
        await eve.checkNow();
        expect(eve.retirementNotice?.isPast, isFalse);

        final day = _controller(repos, body, now: DateTime(2027, 1, 31, 0, 1));
        addTearDown(day.dispose);
        await day.load();
        expect(day.retirementNotice?.isPast, isTrue);
      },
    );

    test('"Later" hides the banner for this session only', () async {
      final repos = openTestRepositories();
      final body = ValueNotifier<String?>(
        _manifest('0.8.0', retirements: _retire070),
      );
      final controller = _controller(repos, body);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.checkNow();

      controller.hideRetirementBanner();
      expect(controller.retirementBanner, isNull);
      // Settings still shows it.
      expect(controller.retirementNotice, isNotNull);

      final relaunched = _controller(repos, body);
      addTearDown(relaunched.dispose);
      await relaunched.load();
      expect(relaunched.retirementBanner, isNotNull);
    });
  });

  group('RetirementBanner', () {
    Future<void> pump(WidgetTester tester, UpdateController controller) =>
        tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: Scaffold(
              body: UpdateScope(
                controller: controller,
                child: const RetirementBanner(),
              ),
            ),
          ),
        );

    testWidgets('shows nothing without a notice', (tester) async {
      final repos = openTestRepositories();
      final body = ValueNotifier<String?>(_manifest('0.8.0'));
      final controller = _controller(repos, body);
      addTearDown(controller.dispose);
      await pump(tester, controller);
      await controller.checkNow();
      await tester.pump();

      expect(find.byKey(const ValueKey('retirement-banner')), findsNothing);
    });

    testWidgets('names the version and the deadline, and "Later" hides it', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final body = ValueNotifier<String?>(
        _manifest('0.8.0', retirements: _retire070),
      );
      final controller = _controller(repos, body);
      addTearDown(controller.dispose);
      await pump(tester, controller);
      await controller.checkNow();
      await tester.pump();

      expect(find.byKey(const ValueKey('retirement-banner')), findsOneWidget);
      expect(
        find.textContaining('(0.7.0) ends on Sunday, January 31, 2027'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('retirement-banner-later')));
      await tester.pump();
      expect(find.byKey(const ValueKey('retirement-banner')), findsNothing);
    });

    testWidgets('after the date it says support has ended', (tester) async {
      final repos = openTestRepositories();
      final body = ValueNotifier<String?>(
        _manifest('0.8.0', retirements: _retire070),
      );
      final controller = _controller(repos, body, now: DateTime(2027, 2, 1));
      addTearDown(controller.dispose);
      await pump(tester, controller);
      await controller.checkNow();
      await tester.pump();

      expect(
        find.textContaining('ended on Sunday, January 31, 2027'),
        findsOneWidget,
      );
    });

    testWidgets('"Get update" opens the newer release the check found', (
      tester,
    ) async {
      final launcher = installFakeUrlLauncher();
      final repos = openTestRepositories();
      final body = ValueNotifier<String?>(
        _manifest('0.8.0', retirements: _retire070),
      );
      final controller = _controller(repos, body);
      addTearDown(controller.dispose);
      await pump(tester, controller);
      await controller.checkNow();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('retirement-banner-update')));
      await tester.pump();
      expect(
        launcher.lastLaunchedUrl,
        'https://github.com/ibanner56/CallersCompendium/releases/tag/v0.8.0',
      );
    });

    testWidgets('"Get update" falls back to the release list', (tester) async {
      final launcher = installFakeUrlLauncher();
      final repos = openTestRepositories();
      final body = ValueNotifier<String?>(
        _manifest('0.6.0', retirements: _retire070),
      );
      final controller = _controller(repos, body, current: '0.7.0-beta');
      addTearDown(controller.dispose);
      await pump(tester, controller);
      await controller.checkNow();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('retirement-banner-update')));
      await tester.pump();
      expect(launcher.lastLaunchedUrl, kReleasesPageUrl);
    });
  });
}
