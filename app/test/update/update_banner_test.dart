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

import '../support/fake_url_launcher.dart';
import '../support/test_repositories.dart';

String _manifest(String version) =>
    '''
{
  "manifestSchemaVersion": 1,
  "channel": "stable",
  "version": "$version",
  "releaseNotesUrl": "https://github.com/ibanner56/CallersCompendium/releases/tag/v$version",
  "pubDate": "2026-08-01T00:00:00Z",
  "artifacts": [
    {"platform": "linux", "arch": "x64", "url": "https://example.com/a", "sha256": "x", "size": 1}
  ]
}
''';

/// Builds a controller whose fetch returns whatever [bodyRef.value] currently
/// holds, so a single test can change the "published" manifest between checks.
UpdateController _controller(
  CompendiumRepositories repos,
  ValueNotifier<String?> bodyRef,
) {
  return UpdateController(
    repos.settings,
    service: UpdateService(
      fetcher: (channel, {http.Client? client}) async => bodyRef.value,
    ),
    currentVersion: SemVer.tryParse('0.1.0'),
    platform: UpdatePlatform.linux,
    arch: UpdateArch.x64,
  );
}

Future<void> _pump(WidgetTester tester, UpdateController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: UpdateScope(controller: controller, child: const UpdateBanner()),
      ),
    ),
  );
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('shows nothing until a newer version is found', (tester) async {
    final repos = openTestRepositories();
    final body = ValueNotifier<String?>(null);
    final controller = _controller(repos, body);
    addTearDown(controller.dispose);
    addTearDown(body.dispose);

    await _pump(tester, controller);
    expect(find.byKey(const ValueKey('update-banner')), findsNothing);

    // A check that finds nothing keeps the banner hidden.
    await controller.checkNow();
    await tester.pump();
    expect(find.byKey(const ValueKey('update-banner')), findsNothing);
  });

  testWidgets('shows the banner when a newer version is found', (tester) async {
    final repos = openTestRepositories();
    final body = ValueNotifier<String?>(_manifest('0.2.0'));
    final controller = _controller(repos, body);
    addTearDown(controller.dispose);
    addTearDown(body.dispose);

    await _pump(tester, controller);
    await controller.checkNow();
    await tester.pump();

    expect(find.byKey(const ValueKey('update-banner')), findsOneWidget);
    expect(find.textContaining('0.2.0'), findsOneWidget);
  });

  testWidgets('does not show an older/equal version', (tester) async {
    final repos = openTestRepositories();
    final body = ValueNotifier<String?>(_manifest('0.1.0'));
    final controller = _controller(repos, body);
    addTearDown(controller.dispose);
    addTearDown(body.dispose);

    await _pump(tester, controller);
    await controller.checkNow();
    await tester.pump();
    expect(find.byKey(const ValueKey('update-banner')), findsNothing);
  });

  testWidgets(
    'dismiss remembers the version and does not show it again until newer',
    (tester) async {
      final repos = openTestRepositories();
      final body = ValueNotifier<String?>(_manifest('0.2.0'));
      final controller = _controller(repos, body);
      addTearDown(controller.dispose);
      addTearDown(body.dispose);

      await _pump(tester, controller);
      await controller.checkNow();
      await tester.pump();
      expect(find.byKey(const ValueKey('update-banner')), findsOneWidget);

      // Dismiss 0.2.0.
      await tester.tap(find.byKey(const ValueKey('update-banner-dismiss')));
      await tester.pump();
      expect(find.byKey(const ValueKey('update-banner')), findsNothing);

      // The dismissed version was persisted.
      expect(await repos.settings.get('update_dismissed_version'), '0.2.0');

      // Re-checking the *same* version keeps it hidden (no nagging).
      await controller.checkNow();
      await tester.pump();
      expect(find.byKey(const ValueKey('update-banner')), findsNothing);

      // A strictly-newer version reappears.
      body.value = _manifest('0.3.0');
      await controller.checkNow();
      await tester.pump();
      expect(find.byKey(const ValueKey('update-banner')), findsOneWidget);
      expect(find.textContaining('0.3.0'), findsOneWidget);
    },
  );

  testWidgets('primary action opens the release notes URL', (tester) async {
    final launcher = installFakeUrlLauncher();
    final repos = openTestRepositories();
    final body = ValueNotifier<String?>(_manifest('0.2.0'));
    final controller = _controller(repos, body);
    addTearDown(controller.dispose);
    addTearDown(body.dispose);

    await _pump(tester, controller);
    await controller.checkNow();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('update-banner-view')));
    await tester.pump();

    expect(
      launcher.lastLaunchedUrl,
      'https://github.com/ibanner56/CallersCompendium/releases/tag/v0.2.0',
    );
  });

  testWidgets('a dismissed version persists across controller instances', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final body = ValueNotifier<String?>(_manifest('0.2.0'));
    addTearDown(body.dispose);

    // First controller: find, dismiss, persist.
    final first = _controller(repos, body);
    await _pump(tester, first);
    await first.checkNow();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('update-banner-dismiss')));
    await tester.pump();
    first.dispose();

    // A fresh controller over the same store loads the dismissed version.
    final second = _controller(repos, body);
    addTearDown(second.dispose);
    await second.load();
    await _pump(tester, second);
    await second.checkNow();
    await tester.pump();
    expect(find.byKey(const ValueKey('update-banner')), findsNothing);
  });
}
