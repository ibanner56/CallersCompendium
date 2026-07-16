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

import '../support/test_repositories.dart';

/// Builds a controller with a fetcher that records the requested channel and
/// returns no update (so checks are fast, silent no-ops).
UpdateController _controller(
  CompendiumRepositories repos,
  List<UpdateChannel> fetched,
) {
  return UpdateController(
    repos.settings,
    service: UpdateService(
      fetcher: (channel, {http.Client? client}) async {
        fetched.add(channel);
        return null;
      },
    ),
    currentVersion: SemVer.tryParse('0.1.0'),
    platform: UpdatePlatform.linux,
    arch: UpdateArch.x64,
  );
}

Future<void> _pump(WidgetTester tester, UpdateController controller) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await controller.load();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: UpdateScope(
          controller: controller,
          child: const UpdatesSection(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

SwitchListTile _switch(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(find.byKey(ValueKey(key)));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('auto-check and beta are OFF by default', (tester) async {
    final repos = openTestRepositories();
    final fetched = <UpdateChannel>[];
    final controller = _controller(repos, fetched);
    addTearDown(controller.dispose);

    await _pump(tester, controller);

    expect(_switch(tester, 'updates-auto-toggle').value, isFalse);
    expect(_switch(tester, 'updates-beta-toggle').value, isFalse);
  });

  testWidgets('manual check works with beta off and fetches stable', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final fetched = <UpdateChannel>[];
    final controller = _controller(repos, fetched);
    addTearDown(controller.dispose);

    await _pump(tester, controller);
    await tester.tap(find.byKey(const ValueKey('updates-check-now')));
    await tester.pumpAndSettle();

    expect(fetched, [UpdateChannel.stable]);
    expect(controller.status, UpdateCheckStatus.noUpdate);
  });

  testWidgets('beta opt-in persists and switches the fetched channel', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final fetched = <UpdateChannel>[];
    final controller = _controller(repos, fetched);
    addTearDown(controller.dispose);

    await _pump(tester, controller);

    // Turn beta on.
    await tester.tap(find.byKey(const ValueKey('updates-beta-toggle')));
    await tester.pumpAndSettle();
    expect(controller.betaChannel, isTrue);
    expect(_switch(tester, 'updates-beta-toggle').value, isTrue);
    expect(await repos.settings.get('update_beta_channel'), isTrue);

    // Now a manual check fetches the beta channel.
    await tester.tap(find.byKey(const ValueKey('updates-check-now')));
    await tester.pumpAndSettle();
    expect(fetched.last, UpdateChannel.beta);

    // Turn beta back off → checks return to stable.
    await tester.tap(find.byKey(const ValueKey('updates-beta-toggle')));
    await tester.pumpAndSettle();
    expect(await repos.settings.get('update_beta_channel'), isFalse);
    await tester.tap(find.byKey(const ValueKey('updates-check-now')));
    await tester.pumpAndSettle();
    expect(fetched.last, UpdateChannel.stable);
  });

  testWidgets('auto-check opt-in persists', (tester) async {
    final repos = openTestRepositories();
    final fetched = <UpdateChannel>[];
    final controller = _controller(repos, fetched);
    addTearDown(controller.dispose);

    await _pump(tester, controller);
    await tester.tap(find.byKey(const ValueKey('updates-auto-toggle')));
    await tester.pumpAndSettle();

    expect(controller.autoCheck, isTrue);
    expect(await repos.settings.get('update_auto_check'), isTrue);
  });

  testWidgets('a fresh controller loads persisted prefs', (tester) async {
    final repos = openTestRepositories();
    await repos.settings.set('update_beta_channel', true);
    await repos.settings.set('update_auto_check', true);

    final controller = _controller(repos, <UpdateChannel>[]);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(_switch(tester, 'updates-beta-toggle').value, isTrue);
    expect(_switch(tester, 'updates-auto-toggle').value, isTrue);
    expect(controller.channel, UpdateChannel.beta);
  });

  testWidgets('maybeAutoCheck only checks when auto-check is on', (
    tester,
  ) async {
    // Auto off → no fetch.
    final reposOff = openTestRepositories();
    final fetchedOff = <UpdateChannel>[];
    final off = _controller(reposOff, fetchedOff);
    addTearDown(off.dispose);
    await off.load();
    await off.maybeAutoCheck();
    expect(fetchedOff, isEmpty);

    // Auto on → one fetch on the persisted channel.
    final reposOn = openTestRepositories();
    await reposOn.settings.set('update_auto_check', true);
    final fetchedOn = <UpdateChannel>[];
    final on = _controller(reposOn, fetchedOn);
    addTearDown(on.dispose);
    await on.load();
    await on.maybeAutoCheck();
    expect(fetchedOn, [UpdateChannel.stable]);
  });
}
