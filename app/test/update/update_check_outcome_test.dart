import 'dart:convert';

import 'package:compendium_app/src/screens/settings/updates_section.dart';
import 'package:compendium_app/src/update/semver.dart';
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

/// FAIL-3: a *manual* check says why it found nothing; the *automatic* check
/// stays silent (ADR-002 §5, erratum 2026-10-29).

String _manifest({
  int schema = 1,
  String platform = 'linux',
  String arch = 'x64',
}) =>
    '''
{
  "manifestSchemaVersion": $schema,
  "channel": "stable",
  "version": "0.2.0",
  "releaseNotesUrl": "https://github.com/ibanner56/CallersCompendium/releases/tag/v0.2.0",
  "pubDate": "2026-08-01T00:00:00Z",
  "artifacts": [
    {
      "platform": "$platform",
      "arch": "$arch",
      "url": "https://example.com/app-0.2.0.bin",
      "sha256": "abcd",
      "size": 1000
    }
  ]
}
''';

UpdateService _service(
  String? body, {
  bool authentic = true,
  String? signature = 'c2ln',
}) => UpdateService(
  fetcher: (channel, {http.Client? client}) async =>
      body == null ? null : utf8.encode(body),
  signatureFetcher: (channel, {http.Client? client}) async => signature,
  signatureVerifier: (bytes, sig) async => authentic,
);

Future<UpdateCheckOutcome> _outcome(UpdateService service) =>
    service.checkManifest(
      channel: UpdateChannel.stable,
      currentVersion: SemVer.tryParse('0.1.0')!,
      platform: UpdatePlatform.linux,
      arch: UpdateArch.x64,
    );

Matcher _failed(UpdateCheckFailure failure) =>
    isA<UpdateCheckFailed>().having((o) => o.failure, 'failure', failure);

UpdateController _controller(CompendiumRepositories repos, UpdateService s) =>
    UpdateController(
      repos.settings,
      service: s,
      currentVersion: SemVer.tryParse('0.1.0'),
      platform: UpdatePlatform.linux,
      arch: UpdateArch.x64,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('UpdateService.checkManifest names the failure', () {
    test('an unreachable manifest is unreachable', () async {
      expect(
        await _outcome(_service(null)),
        _failed(UpdateCheckFailure.unreachable),
      );
    });

    test('a manifest whose signature does not verify is unauthentic', () async {
      expect(
        await _outcome(_service(_manifest(), authentic: false)),
        _failed(UpdateCheckFailure.unauthentic),
      );
    });

    test('an authentic newer schema is an unsupported format', () async {
      expect(
        await _outcome(_service(_manifest(schema: 2))),
        _failed(UpdateCheckFailure.unsupportedFormat),
      );
    });

    test('an authentic artifact for an unknown platform or arch is an '
        'unsupported format', () async {
      expect(
        await _outcome(_service(_manifest(platform: 'plan9'))),
        _failed(UpdateCheckFailure.unsupportedFormat),
      );
      expect(
        await _outcome(_service(_manifest(arch: 'riscv64'))),
        _failed(UpdateCheckFailure.unsupportedFormat),
      );
    });

    test('an unauthentic newer schema is NOT reported as a newer format '
        '(the claim needs the signature first)', () async {
      expect(
        await _outcome(_service(_manifest(schema: 2), authentic: false)),
        _failed(UpdateCheckFailure.unauthentic),
      );
    });

    test('a lower schema, bad JSON and a channel mismatch are malformed, '
        'not newer', () async {
      expect(
        await _outcome(_service(_manifest(schema: 0))),
        _failed(UpdateCheckFailure.malformed),
      );
      expect(
        await _outcome(_service('{not json')),
        _failed(UpdateCheckFailure.malformed),
      );
      final beta = _manifest().replaceFirst('"stable"', '"beta"');
      expect(
        await _outcome(_service(beta)),
        _failed(UpdateCheckFailure.malformed),
      );
    });

    test('a readable manifest is UpdateChecked', () async {
      final outcome = await _outcome(_service(_manifest()));
      expect(outcome, isA<UpdateChecked>());
      expect((outcome as UpdateChecked).result.update, isNotNull);
    });
  });

  group('UpdateController status', () {
    final cases = <String, (String?, bool, UpdateCheckStatus)>{
      'unreachable': (null, true, UpdateCheckStatus.couldNotCheck),
      'unauthentic': (_manifest(), false, UpdateCheckStatus.couldNotCheck),
      'unsupported format': (
        _manifest(schema: 2),
        true,
        UpdateCheckStatus.newerFormat,
      ),
    };

    for (final entry in cases.entries) {
      final (body, authentic, manual) = entry.value;

      test('manual check, ${entry.key}: $manual', () async {
        final repos = openTestRepositories();
        final c = _controller(repos, _service(body, authentic: authentic));
        addTearDown(c.dispose);
        await c.load();
        await c.checkNow();
        expect(c.status, manual);
        expect(c.foundUpdate, isNull);
      });

      test(
        'automatic check, ${entry.key}: stays silent (status untouched)',
        () async {
          final repos = openTestRepositories();
          await repos.settings.set('update_auto_check', true);
          final c = _controller(repos, _service(body, authentic: authentic));
          addTearDown(c.dispose);
          await c.load();
          await c.maybeAutoCheck();
          // Not "No update found": no check completed to make that claim.
          expect(c.status, UpdateCheckStatus.idle);
        },
      );
    }

    test('a manual check that finds the app current says noUpdate', () async {
      final repos = openTestRepositories();
      final c = UpdateController(
        repos.settings,
        service: _service(_manifest()),
        currentVersion: SemVer.tryParse('0.2.0'),
        platform: UpdatePlatform.linux,
        arch: UpdateArch.x64,
      );
      addTearDown(c.dispose);
      await c.load();
      await c.checkNow();
      expect(c.status, UpdateCheckStatus.noUpdate);
    });
  });

  group('Settings status line', () {
    Future<void> pump(WidgetTester tester, UpdateController c) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await c.load();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: UpdateScope(controller: c, child: const UpdatesSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a failed manual check says "Couldn\'t check"', (tester) async {
      final repos = openTestRepositories();
      final c = _controller(repos, _service(null));
      addTearDown(c.dispose);
      await pump(tester, c);
      await tester.tap(find.byKey(const ValueKey('updates-check-now')));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't check for updates"), findsOneWidget);
      expect(find.textContaining('No update found'), findsNothing);
    });

    testWidgets('an authentic unsupported manifest points at the Releases '
        'page', (tester) async {
      final repos = openTestRepositories();
      final c = _controller(repos, _service(_manifest(schema: 2)));
      addTearDown(c.dispose);
      await pump(tester, c);
      await tester.tap(find.byKey(const ValueKey('updates-check-now')));
      await tester.pumpAndSettle();
      expect(
        find.text('A newer version is available from the Releases page.'),
        findsOneWidget,
      );
    });
  });
}
