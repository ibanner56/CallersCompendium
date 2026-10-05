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
  List<(String key, Object local, Object remote)> ties, {
  Duration remoteLater = Duration.zero,
}) async {
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
        updatedAt: candidate.updatedAt.add(remoteLater),
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

/// Queues a tie on one dance whose versions differ only in their figures.
Future<void> _queueDanceTie(
  CompendiumRepositories repos, {
  required List<Figure> local,
  required List<Figure> remote,
}) async {
  await repos.dances.create(
    Dance(
      id: 'd1',
      title: 'Happy Trails',
      authorIds: const [],
      tagIds: const [],
      figures: local,
      customFields: const [],
      hook: '',
      createdAt: _tie,
      updatedAt: _tie,
    ),
  );
  final storage = CompendiumSyncStorage(repos);
  const address = (kind: SyncRecordKind.dance, recordId: 'd1');
  final mine = (await storage.snapshot()).local[address]!;
  final theirs = SyncMergeCandidate.fromBlob(
    SyncRecordBlob(
      kind: SyncRecordKind.dance,
      id: 'd1',
      updatedAt: mine.updatedAt,
      deletedAt: null,
      existenceAt: mine.existenceAt,
      body: {
        ...mine.blob.body,
        'figures': [for (final f in remote) figureToJson(f)],
      },
    ),
  );
  final plan = const SyncMergeEngine().plan(
    local: {address: mine},
    baseline: const {},
    peers: [
      {address: theirs},
    ],
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
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      isNull,
      reason: 'no version is shown as chosen until the user picks one',
    );
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

  group('showing what differs', () {
    testWidgets('a single conflict shows its whole comparison at once', (
      tester,
    ) async {
      final repos = await _pump(tester);
      await tester.runAsync(
        () => _queueTie(repos, [('theme_mode', 'dark', 'light')]),
      );
      await _open(tester);

      expect(
        find.byKey(const ValueKey('sync-conflict-comparison-theme_mode')),
        findsOneWidget,
      );
      expect(find.text('Show differences'), findsNothing);
    });

    testWidgets('several conflicts stay compact, each opening its own '
        'comparison', (tester) async {
      final repos = await _pump(tester, size: const Size(400, 1400));
      await tester.runAsync(
        () => _queueTie(repos, [
          ('theme_mode', 'dark', 'light'),
          ('reduce_motion', true, false),
        ]),
      );
      await _open(tester);

      expect(find.text('Show differences'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('sync-conflict-comparison-theme_mode')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('sync-conflict-show-differences-theme_mode')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sync-conflict-differences-page')),
        findsOneWidget,
        reason: 'a phone gets a page of its own',
      );
      expect(find.text('This device: dark'), findsOneWidget);
      expect(find.text('Another device: light'), findsOneWidget);
    });

    testWidgets('a collection says which entries differ, not how many each '
        'has', (tester) async {
      final repos = await _pump(tester);
      await tester.runAsync(
        () => _queueTie(repos, [
          (
            'shorthand_mappings',
            [
              {'token': 'bs', 'figures': <Object?>[]},
              {'token': 'ca', 'figures': <Object?>[]},
            ],
            [
              {'token': 'bs', 'figures': <Object?>[]},
              {'token': 'nbs', 'figures': <Object?>[]},
            ],
          ),
        ]),
      );
      await _open(tester);

      expect(
        find.text('1 only on this device · 1 only on the other device'),
        findsOneWidget,
      );
      expect(find.text('Only on this device'), findsOneWidget);
      expect(find.text('ca'), findsOneWidget);
      expect(find.text('Only on the other device'), findsOneWidget);
      expect(find.text('nbs'), findsOneWidget);
      expect(find.text('1 more is the same on both'), findsOneWidget);
    });

    testWidgets('each version says when it was changed, when that tells '
        'them apart', (tester) async {
      final repos = await _pump(tester);
      await tester.runAsync(
        () => _queueTie(repos, [
          (
            'custom_dialects',
            [
              {'name': 'Mine'},
            ],
            [
              {'name': 'Theirs'},
            ],
          ),
        ], remoteLater: const Duration(days: 2)),
      );
      await _open(tester);

      // One line per version, two days apart (dates themselves depend on the
      // test machine's time zone).
      expect(find.textContaining('Changed '), findsNWidgets(2));
    });

    testWidgets('an exact tie shows no times: they would be the same', (
      tester,
    ) async {
      final repos = await _pump(tester);
      await tester.runAsync(
        () => _queueTie(repos, [('theme_mode', 'dark', 'light')]),
      );
      await _open(tester);

      expect(find.textContaining('Changed '), findsNothing);
    });

    testWidgets('a dance shows the figures that differ, by section', (
      tester,
    ) async {
      final repos = await _pump(tester, size: const Size(400, 1400));
      await tester.runAsync(
        () => _queueDanceTie(
          repos,
          local: [
            Figure(move: 'swing', params: const {'beats': 16}),
            Figure(move: 'circle', params: const {'beats': 8}),
          ],
          remote: [
            Figure(move: 'swing', params: const {'beats': 16}),
            Figure(move: 'star', params: const {'beats': 8}),
          ],
        ),
      );
      await _open(tester);

      expect(find.text('Differs in: Figures'), findsOneWidget);
      // Only the figure that differs is shown, under the section it starts
      // in; the swing both versions share is not repeated.
      expect(find.text('A2'), findsOneWidget);
      expect(find.text('This device: circle left 4 places'), findsOneWidget);
      expect(find.text('Another device: star right 4 places'), findsOneWidget);
      expect(find.text('A1'), findsNothing);
    });
  });
}
