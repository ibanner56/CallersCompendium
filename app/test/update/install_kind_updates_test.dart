import 'dart:convert';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/screens/settings/updates_section.dart';
import 'package:compendium_app/src/update/install_kind.dart';
import 'package:compendium_app/src/update/semver.dart';
import 'package:compendium_app/src/update/update_banner.dart';
import 'package:compendium_app/src/update/update_controller.dart';
import 'package:compendium_app/src/update/update_manifest.dart';
import 'package:compendium_app/src/update/update_scope.dart';
import 'package:compendium_app/src/update/update_service.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

const _manifest = '''
{
  "manifestSchemaVersion": 1,
  "channel": "stable",
  "version": "0.2.0",
  "releaseNotesUrl": "https://github.com/ibanner56/CallersCompendium/releases/tag/v0.2.0",
  "pubDate": "2026-08-01T00:00:00Z",
  "artifacts": [
    {"platform": "windows", "arch": "x64", "url": "https://example.com/a.exe", "sha256": "x", "size": 1}
  ]
}
''';

({UpdateController controller, List<UpdateChannel> fetched}) _make(
  CompendiumRepositories repos,
  InstallKind kind, {
  UpdatePlatform platform = UpdatePlatform.windows,
}) {
  final fetched = <UpdateChannel>[];
  final controller = UpdateController(
    repos.settings,
    service: UpdateService(
      fetcher: (channel, {http.Client? client}) async {
        fetched.add(channel);
        return utf8.encode(_manifest);
      },
      signatureFetcher: (channel, {http.Client? client}) async => 'sig',
      signatureVerifier: (bytes, sig) async => true,
    ),
    currentVersion: SemVer.tryParse('0.1.0'),
    platform: platform,
    arch: UpdateArch.x64,
    installKind: kind,
  );
  return (controller: controller, fetched: fetched);
}

Future<void> _pump(
  WidgetTester tester,
  UpdateController controller,
  Widget child,
) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await controller.load();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: UpdateScope(controller: controller, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('store build', () {
    test('never fetches the manifest, manually or automatically', () async {
      final repos = openTestRepositories();
      final made = _make(repos, InstallKind.store);
      addTearDown(made.controller.dispose);
      await made.controller.load();
      await made.controller.setAutoCheck(true);

      await made.controller.checkNow();
      await made.controller.maybeAutoCheck();

      expect(made.fetched, isEmpty);
      expect(made.controller.checksForUpdates, isFalse);
      expect(made.controller.status, UpdateCheckStatus.idle);
      expect(made.controller.foundUpdate, isNull);
    });

    testWidgets('Settings shows only the store note', (tester) async {
      final repos = openTestRepositories();
      final made = _make(repos, InstallKind.store);
      addTearDown(made.controller.dispose);
      await _pump(tester, made.controller, const UpdatesSection());

      expect(find.byKey(const ValueKey('updates-store')), findsOneWidget);
      expect(find.byKey(const ValueKey('updates-check-now')), findsNothing);
      expect(find.byKey(const ValueKey('updates-beta-toggle')), findsNothing);
      expect(find.byKey(const ValueKey('updates-auto-toggle')), findsNothing);
    });
  });

  group('portable build', () {
    test('checks, but offers no installer', () async {
      final repos = openTestRepositories();
      final made = _make(repos, InstallKind.portable);
      addTearDown(made.controller.dispose);
      await made.controller.load();

      await made.controller.checkNow();

      expect(made.fetched, [UpdateChannel.stable]);
      expect(made.controller.foundUpdate, isNotNull);
      expect(made.controller.canAssistDownload, isFalse);
    });

    testWidgets('banner says to download the new archive', (tester) async {
      final repos = openTestRepositories();
      final made = _make(repos, InstallKind.portable);
      addTearDown(made.controller.dispose);
      await _pump(tester, made.controller, const UpdateBanner());
      await made.controller.checkNow();
      await tester.pump();

      expect(find.textContaining('portable copy'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('update-banner-download')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('update-banner-view')), findsOneWidget);
    });

    testWidgets('Settings points at the release, not an installer', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final made = _make(repos, InstallKind.portable);
      addTearDown(made.controller.dispose);
      await _pump(tester, made.controller, const UpdatesSection());
      expect(find.byKey(const ValueKey('updates-portable')), findsNothing);

      await made.controller.checkNow();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('updates-portable')), findsOneWidget);
      expect(find.byKey(const ValueKey('updates-download')), findsNothing);
      expect(find.byKey(const ValueKey('updates-check-now')), findsOneWidget);
    });
  });

  group('standard build', () {
    test('keeps the assisted download', () async {
      final repos = openTestRepositories();
      final made = _make(repos, InstallKind.standard);
      addTearDown(made.controller.dispose);
      await made.controller.load();

      await made.controller.checkNow();

      expect(made.controller.canAssistDownload, isTrue);
    });

    testWidgets('banner keeps the plain message', (tester) async {
      final repos = openTestRepositories();
      final made = _make(repos, InstallKind.standard);
      addTearDown(made.controller.dispose);
      await _pump(tester, made.controller, const UpdateBanner());
      await made.controller.checkNow();
      await tester.pump();

      expect(find.textContaining('portable copy'), findsNothing);
      expect(
        find.byKey(const ValueKey('update-banner-download')),
        findsOneWidget,
      );
    });
  });
}
