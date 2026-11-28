import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart' show AppData;
import 'package:compendium_app/src/data/calendar_import.dart';
import 'package:compendium_app/src/data/calendar_import_settings.dart';
import 'package:compendium_app/src/data/calendar_startup.dart';
import 'package:compendium_app/src/data/settings_keys.dart'
    show kSyncEnabledKey;
import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/full_app_harness.dart';
import 'support/noop_sync_transport.dart';
import 'support/sync_test_network.dart';

/// The startup calendar import and Device Sync's launch pass: with sync on,
/// add-drafts mode waits for that pass, so drafts another device already
/// imported (and this launch's pass pulls) are not created a second time.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const url = 'https://calendar.example/basic.ics';

  /// Two events a week and two weeks out from the test's own clock (the
  /// fake-async clock the app also reads), so no fixed date can fall out of
  /// the import window.
  String feed() {
    String day(int days) {
      final d = clock.now().add(Duration(days: days));
      return '${d.year.toString().padLeft(4, '0')}'
          '${d.month.toString().padLeft(2, '0')}'
          '${d.day.toString().padLeft(2, '0')}';
    }

    return [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'BEGIN:VEVENT',
      'UID:a',
      'DTSTART;VALUE=DATE:${day(7)}',
      'SUMMARY:Contra A',
      'END:VEVENT',
      'BEGIN:VEVENT',
      'UID:b',
      'DTSTART;VALUE=DATE:${day(14)}',
      'SUMMARY:Contra B',
      'END:VEVENT',
      'END:VCALENDAR',
      '',
    ].join('\r\n');
  }

  /// What another device's earlier startup import leaves in the library once
  /// a pull has applied it: the same events as drafts, with their keys.
  Future<void> importOnOtherDevice(CompendiumRepositories repos) async {
    final today = clock.now();
    final preview = await buildCalendarImportPreview(
      repos,
      body: feed(),
      feedUrl: url,
      settings: const CalendarImportSettings(),
      today: DateTime(today.year, today.month, today.day),
    );
    await commitCalendarImport(
      repos,
      chosen: preview.entries,
      untitledTitle: 'Untitled event',
      now: clock.now().toUtc(),
    );
  }

  Future<AppData> appWithStartupDrafts({required bool sync}) async {
    final appData = openTestAppData();
    final settings = appData.repositories.settings;
    await settings.set(kCalendarImportOnStartupKey, true);
    await settings.set(
      kCalendarStartupModeKey,
      CalendarStartupMode.addDrafts.name,
    );
    await settings.set(kCalendarFeedUrlKey, url);
    if (sync) await settings.set(kSyncEnabledKey, true);
    return appData;
  }

  Future<SyncCoordinator?> Function(CompendiumRepositories) syncFactory(
    Future<void> Function(CompendiumRepositories repos) pass,
  ) =>
      (repositories) async => SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-b',
        store: CompendiumSyncCoordinatorStore(repositories),
        transport: NoopSyncCoordinatorTransport(),
        passOperation: ({initialStore}) async {
          await pass(repositories);
          return const SyncPassResult(SyncPassStatus.completed);
        },
      );

  Future<void> pumpApp(
    WidgetTester tester,
    AppData appData, {
    required Future<String> Function(String url) fetcher,
    Future<SyncCoordinator?> Function(CompendiumRepositories)? syncFactory,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: NoopWindowService(appData.repositories.settings),
        integrityCheck: () async => true,
        syncCoordinatorFactory: syncFactory,
        syncNetworkClassifier: const UnmeteredSyncNetwork(),
        calendarStartupFetcher: fetcher,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<String?>> eventKeys(AppData appData) async => [
    for (final p in await appData.repositories.programs.listAll())
      p.calendarEventKey,
  ];

  testWidgets('sync on: the startup run waits for the launch pull, and adds '
      'no duplicate of a draft another device imported', (tester) async {
    final appData = await appWithStartupDrafts(sync: true);
    final pull = Completer<void>();
    var fetches = 0;
    await pumpApp(
      tester,
      appData,
      fetcher: (_) async {
        fetches++;
        return feed();
      },
      syncFactory: syncFactory((repos) async {
        // The pull completes after the app has started.
        await pull.future;
        await importOnOtherDevice(repos);
      }),
    );
    expect(fetches, 0, reason: 'no fetch while the launch pull runs');

    pull.complete();
    await tester.pumpAndSettle();

    expect(fetches, 1);
    final keys = await eventKeys(appData);
    expect(keys, hasLength(2), reason: 'only the other device\'s two drafts');
    expect(keys.toSet(), hasLength(2), reason: 'no duplicate key');
    expect(keys, everyElement(isNotNull));
  });

  testWidgets('a setting changed during the wait is what the run sees: the '
      'switch turned off fetches nothing', (tester) async {
    final appData = await appWithStartupDrafts(sync: true);
    final pull = Completer<void>();
    var fetches = 0;
    await pumpApp(
      tester,
      appData,
      fetcher: (_) async {
        fetches++;
        return feed();
      },
      syncFactory: syncFactory((_) => pull.future),
    );
    await appData.repositories.settings.set(kCalendarImportOnStartupKey, false);
    pull.complete();
    await tester.pumpAndSettle();
    expect(fetches, 0);
    expect(await eventKeys(appData), isEmpty);
  });

  test('the bound the User Guide quotes is the one the code uses', () {
    // The bundled mirror of docs/user/settings.md, which the user-docs gate
    // keeps identical to it.
    final guide = File('assets/docs/user/settings.md').readAsStringSync();
    expect(
      guide,
      contains(
        'waits up to ${kCalendarStartupSyncWait.inSeconds} seconds for the '
        'sync\n  the app runs when it starts',
      ),
    );
  });

  testWidgets('sync off: the startup run is not held back, and adds drafts '
      'as before', (tester) async {
    final appData = await appWithStartupDrafts(sync: false);
    var fetches = 0;
    await pumpApp(
      tester,
      appData,
      fetcher: (_) async {
        fetches++;
        return feed();
      },
    );
    // pumpAndSettle advances no timer to its deadline, so nothing waited.
    expect(fetches, 1);
    expect(await eventKeys(appData), hasLength(2));
  });

  testWidgets('a launch pull that never completes delays the run by at most '
      'the bound', (tester) async {
    final appData = await appWithStartupDrafts(sync: true);
    final never = Completer<void>();
    var fetches = 0;
    await pumpApp(
      tester,
      appData,
      fetcher: (_) async {
        fetches++;
        return feed();
      },
      syncFactory: syncFactory((_) => never.future),
    );
    expect(fetches, 0);

    // The wait starts during the pumpAndSettle above, which advances fake
    // time by well under a second; hence a second's margin either side.
    await tester.pump(kCalendarStartupSyncWait - const Duration(seconds: 1));
    expect(fetches, 0, reason: 'still inside the bound');

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(fetches, 1, reason: 'the bound has passed');
    expect(await eventKeys(appData), hasLength(2));
  });

  testWidgets('a launch pull that fails does not stop the run', (tester) async {
    final appData = await appWithStartupDrafts(sync: true);
    final fail = Completer<void>();
    var fetches = 0;
    await pumpApp(
      tester,
      appData,
      fetcher: (_) async {
        fetches++;
        return feed();
      },
      syncFactory: syncFactory((_) async {
        await fail.future;
        throw StateError('pull failed');
      }),
    );
    expect(fetches, 0);
    fail.complete();
    await tester.pumpAndSettle();
    expect(fetches, 1);
    expect(await eventKeys(appData), hasLength(2));
  });
}
