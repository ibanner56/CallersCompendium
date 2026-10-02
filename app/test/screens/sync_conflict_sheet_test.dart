import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/sync_conflict_sheet.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

final _tie = DateTime.utc(2026, 9, 30, 12);

/// Queues a §6.3 tie on [key] exactly as a pass would: this device holds
/// [local], another device holds [remote] at the same `updatedAt`.
Future<void> _queueTie(
  CompendiumRepositories repos,
  List<(String key, Object local, Object remote)> ties,
) async {
  final storage = CompendiumSyncStorage(repos);
  final local = <SyncRecordAddress, SyncMergeCandidate?>{};
  final peer = <SyncRecordAddress, SyncMergeCandidate?>{};
  for (final (key, mine, theirs) in ties) {
    await repos.settings.set(key, mine, at: _tie);
    final address = (kind: SyncRecordKind.setting, recordId: key);
    final candidate = (await storage.snapshot()).local[address]!;
    local[address] = candidate;
    peer[address] = SyncMergeCandidate.fromBlob(
      SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: key,
        updatedAt: candidate.updatedAt,
        deletedAt: null,
        existenceAt: candidate.existenceAt,
        body: {'value': theirs},
      ),
    );
  }
  final plan = const SyncMergeEngine().plan(
    local: local,
    baseline: const {},
    peers: [peer],
  );
  await storage.refreshConflictReviews(plan.reviews);
}

Future<CompendiumRepositories> _pump(
  WidgetTester tester, {
  Size size = const Size(400, 900),
}) async {
  final repos = openTestRepositories();
  // The view, not just the render surface: the sheet reads its width from
  // MediaQuery to choose between a bottom sheet and a dialog.
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('open'),
              onPressed: () => showSyncConflictSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  return repos;
}

Future<void> _open(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('names the setting and both versions, and preselects '
      'nothing', (tester) async {
    final repos = await _pump(tester);
    await tester.runAsync(
      () => _queueTie(repos, [('theme_mode', 'dark', 'light')]),
    );

    await _open(tester);

    expect(
      find.byKey(const ValueKey('sync-conflict-bottom-sheet')),
      findsOneWidget,
    );
    expect(find.text('Choose which version to keep'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);
    expect(find.text('dark'), findsOneWidget);
    expect(find.text('Another device'), findsOneWidget);
    expect(find.text('light'), findsOneWidget);
    final apply = tester.widget<FilledButton>(
      find.byKey(const ValueKey('sync-conflict-apply')),
    );
    expect(apply.onPressed, isNull, reason: 'a choice is only the user\'s');
  });

  testWidgets('keeping the other device\'s version writes it and closes '
      'the choice', (tester) async {
    final repos = await _pump(tester);
    await tester.runAsync(
      () => _queueTie(repos, [('theme_mode', 'dark', 'light')]),
    );
    await _open(tester);

    await tester.tap(find.text('Another device'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('sync-conflict-apply')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.byType(SyncConflictChoice), findsNothing);
    final value = await tester.runAsync(() => repos.settings.get('theme_mode'));
    expect(value, 'light');
    final remaining = await tester.runAsync(() => syncConflictCount(repos));
    expect(remaining, 0);
  });

  testWidgets('deciding later changes nothing', (tester) async {
    final repos = await _pump(tester);
    await tester.runAsync(
      () => _queueTie(repos, [('theme_mode', 'dark', 'light')]),
    );
    await _open(tester);

    await tester.tap(find.byKey(const ValueKey('sync-conflict-later')));
    await tester.pumpAndSettle();

    expect(find.byType(SyncConflictChoice), findsNothing);
    expect(
      await tester.runAsync(() => repos.settings.get('theme_mode')),
      'dark',
    );
    expect(await tester.runAsync(() => syncConflictCount(repos)), 1);
  });

  testWidgets('opens as a dialog on a wide window', (tester) async {
    final repos = await _pump(tester, size: const Size(1000, 800));
    await tester.runAsync(
      () => _queueTie(repos, [('theme_mode', 'dark', 'light')]),
    );

    await _open(tester);

    expect(find.byKey(const ValueKey('sync-conflict-dialog')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sync-conflict-bottom-sheet')),
      findsNothing,
    );
  });

  testWidgets('"keep all" chooses for every item, and the user still '
      'confirms', (tester) async {
    final repos = await _pump(tester, size: const Size(400, 1400));
    await tester.runAsync(
      () => _queueTie(repos, [
        ('theme_mode', 'dark', 'light'),
        ('reduce_motion', true, false),
      ]),
    );
    await _open(tester);

    await tester.tap(
      find.byKey(const ValueKey('sync-conflict-all-other-device')),
    );
    await tester.pump();
    expect(
      await tester.runAsync(() => repos.settings.get('theme_mode')),
      'dark',
      reason: 'choosing is not saving',
    );

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('sync-conflict-apply')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(
      await tester.runAsync(() => repos.settings.get('theme_mode')),
      'light',
    );
    expect(
      await tester.runAsync(() => repos.settings.get('reduce_motion')),
      false,
    );
  });
}
