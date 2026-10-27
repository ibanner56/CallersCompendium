import 'dart:async';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/user_figures_scope.dart';
import 'package:compendium_app/src/screens/sync_conflict_details.dart';
import 'package:compendium_app/src/screens/sync_conflict_sheet.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
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

/// Queues a tie on a record already in the library, whose other version is
/// this device's with [edit] applied.
Future<void> _queueRecordTie(
  CompendiumRepositories repos,
  SyncRecordKind kind,
  String id,
  Map<String, Object?> Function(Map<String, Object?> body) edit,
) async {
  final storage = CompendiumSyncStorage(repos);
  final address = (kind: kind, recordId: id);
  final mine = (await storage.snapshot()).local[address]!;
  final theirs = SyncMergeCandidate.fromBlob(
    SyncRecordBlob(
      kind: kind,
      id: id,
      updatedAt: mine.updatedAt,
      deletedAt: null,
      existenceAt: mine.existenceAt,
      body: edit({...mine.blob.body}),
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

Dance _dance(
  String id, {
  String title = 'Happy Trails',
  List<Figure> figures = const [],
  List<DanceLink> links = const [],
  List<SourceCitation> sourceCitations = const [],
}) => Dance(
  id: id,
  title: title,
  authorIds: const [],
  tagIds: const [],
  figures: figures,
  customFields: const [],
  hook: '',
  links: links,
  sourceCitations: sourceCitations,
  createdAt: _tie,
  updatedAt: _tie,
);

Program _program({
  DateTime? eventDate,
  String? venue,
  String? venueId,
  List<ProgramSlot> slots = const [],
}) => Program(
  id: 'p1',
  title: 'Friday dance',
  eventDate: eventDate,
  venue: venue,
  venueId: venueId,
  slots: slots,
  createdAt: _tie,
  updatedAt: _tie,
);

Map<String, Object?> _slot(int position, {String? danceId, int? minutes}) => {
  'id': 's$position',
  'position': position,
  'danceId': ?danceId,
  'isAlt': false,
  'danceMinutes': ?minutes,
};

Future<CompendiumRepositories> _pump(
  WidgetTester tester, {
  Size size = const Size(400, 900),
  Future<void> Function(CompendiumRepositories repos)? seed,
}) async {
  final repos = openTestRepositories();
  final figures = UserFiguresController(repos.userGlossary);
  addTearDown(figures.dispose);
  if (seed != null) {
    // Written before the user's figures are watched, on the test's clock,
    // which then reads them as the test pumps.
    await tester.runAsync(() => seed(repos));
    unawaited(figures.start());
  }
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
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: UserFiguresScope(controller: figures, child: child!),
      ),
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

/// Queues a tie on the user's notes on each of [figureIds] (#709).
Future<void> _queueNoteTie(
  CompendiumRepositories repos,
  List<String> figureIds,
) async {
  final storage = CompendiumSyncStorage(repos);
  final local = <SyncRecordAddress, SyncMergeCandidate?>{};
  final peer = <SyncRecordAddress, SyncMergeCandidate?>{};
  for (final id in figureIds) {
    await repos.figureNotes.set(id, 'Mine.', at: _tie);
    final address = (kind: SyncRecordKind.figureNote, recordId: id);
    final candidate = (await storage.snapshot()).local[address]!;
    local[address] = candidate;
    peer[address] = SyncMergeCandidate.fromBlob(
      syncRecordBlobForEntity(
        SyncRecordKind.figureNote,
        FigureNote(figureId: id, notes: 'Theirs.'),
        updatedAt: candidate.updatedAt,
        existenceAt: candidate.existenceAt,
      )!,
    );
  }
  final plan = const SyncMergeEngine().plan(
    local: local,
    baseline: const {},
    peers: [peer],
  );
  await storage.refreshConflictReviews(plan.reviews);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('a conflict on notes names the built-in figure, as the active '
      'dialect names it (#709)', (tester) async {
    final repos = openTestRepositories();
    tester.view
      ..physicalSize = const Size(400, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dialect = ValueNotifier(
      Dialect(name: 'Twirly', moves: const {'swing': 'twirl'}),
    );
    addTearDown(dialect.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => ActiveDialectScope(
          notifier: dialect,
          child: RepositoriesScope(repositories: repos, child: child!),
        ),
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
    await tester.runAsync(
      () => _queueNoteTie(repos, [
        'swing',
        'pull_by_dancers',
        'no-longer-a-figure',
      ]),
    );
    await _open(tester);

    expect(find.text('Your notes on twirl'), findsOneWidget);
    expect(
      find.text('Your notes on pull by (neighbors)'),
      findsOneWidget,
      reason: 'qualified as the Glossary qualifies it',
    );
    expect(
      find.text('Your notes on a figure'),
      findsOneWidget,
      reason: 'a figure the taxonomy no longer has is named by kind',
    );
    expect(find.textContaining('no-longer-a-figure'), findsNothing);
  });

  testWidgets('a long note is clipped in the choice, and shown whole in '
      'the comparison (#709)', (tester) async {
    final repos = await _pump(tester, size: const Size(400, 1400));
    await tester.runAsync(() => _queueNoteTie(repos, ['swing']));
    await _open(tester);

    final choice = tester.widget<Text>(find.text('Mine.').first);
    expect(choice.maxLines, 3);
    expect(choice.overflow, TextOverflow.ellipsis);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text && w.data == 'This device: Mine.' && w.maxLines == null,
      ),
      findsOneWidget,
    );
  });

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
    test('a reference to a merged-away record is not a difference', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      List<String> differing({
        Map<SyncRecordKind, Map<String, String>> aliases = const {},
      }) => [
        for (final field in syncConflictDifferingFields(
          l10n,
          SyncRecordKind.dance,
          {
            'title': 'Hey Day',
            'authorIds': ['c1'],
          },
          {
            'title': 'Hey Day!',
            'authorIds': ['c2'],
          },
          aliases: aliases,
        ))
          field.key,
      ];

      expect(
        differing(
          aliases: {
            SyncRecordKind.choreographer: {'c2': 'c1'},
          },
        ),
        ['title'],
      );
      expect(differing(), ['title', 'authorIds']);
    });

    test('a part kept for a newer version is not shown as a difference', () {
      final l10n = lookupAppLocalizations(const Locale('en'));

      expect(
        syncConflictDifferingFields(
          l10n,
          SyncRecordKind.publishedSource,
          {'title': 'Contra Book', 'addedLater': 'one'},
          {'title': 'Contra Book!', 'addedLater': 'two'},
        ).map((field) => field.key),
        ['title'],
      );
    });

    test('shows exactly the fields the merge treats as visible, so a tie in '
        'any other field is never put to the user', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      Object? value(String key, String side) =>
          key == 'provenance' ? {'source': side} : side;
      for (final kind in SyncRecordKind.values) {
        final visible = syncUserVisibleFields(kind);
        if (visible == null) continue;
        for (final key in visible.where((path) => !path.contains('.'))) {
          final shown = syncConflictDifferingFields(
            l10n,
            kind,
            {key: value(key, 'contradb')},
            {key: value(key, 'callersbox')},
          ).map((field) => field.key);
          expect(shown, [
            key == 'venueId' ? 'venue' : key,
          ], reason: '${kind.name}.$key is visible to the merge');
        }
        expect(
          syncConflictDifferingFields(
            l10n,
            kind,
            {'provenanceNot': 'a', 'id': 'x'},
            {'provenanceNot': 'b', 'id': 'y'},
          ),
          isEmpty,
          reason: 'a field the merge does not see is not shown',
        );
      }
      expect(
        syncConflictDifferingFields(
          l10n,
          SyncRecordKind.dance,
          {
            'provenance': {'source': 'contradb', 'importedAt': '2026-01-01'},
          },
          {
            'provenance': {'source': 'contradb', 'importedAt': '2026-02-01'},
          },
        ),
        isEmpty,
        reason: "a dance's page shows only where it came from and its licence",
      );
    });

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

    testWidgets('a shorthand for a new figure reads as the line it inserts, '
        'and as its name and values where it can\'t be rendered (#1023)', (
      tester,
    ) async {
      Map<String, Object?> shorthand(String id, String who, {int? beats}) => {
        'token': 'zm',
        'figure': id,
        'name': 'zoom',
        'args': {'who': who},
        'beats': ?beats,
      };
      final repos = await _pump(
        tester,
        size: const Size(900, 1400),
        seed: (repos) => repos.userGlossary.upsert(
          UserGlossaryEntry(
            id: 'zoom-id',
            kindName: UserGlossaryEntryKind.customFigure.name,
            name: 'zoom',
            definition: 'A zoom.',
            description: 'Fast.',
            payload: {
              'template': '{who} {move}',
              'defaultBeats': 8,
              'params': [
                {'key': 'who', 'kind': 'dancerSet'},
              ],
            },
            createdAt: _tie,
          ),
        ),
      );
      await tester.runAsync(
        () => _queueTie(repos, [
          (
            'user_figure_shorthands',
            [shorthand('zoom-id', 'role2s')],
            [shorthand('zoom-id', 'role1s', beats: 4)],
          ),
        ]),
      );
      await _open(tester);
      expect(find.textContaining('robins zoom'), findsOneWidget);
      expect(find.textContaining('larks zoom · 4 beats'), findsOneWidget);
      expect(find.text('Shorthands for your new figures'), findsWidgets);
    });

    testWidgets('a shorthand for a figure this device lacks reads as its name '
        'and values (#1023)', (tester) async {
      Map<String, Object?> shorthand(String who) => {
        'token': 'zm',
        'figure': 'elsewhere-id',
        'name': 'zoom',
        'args': {'who': who},
      };
      final repos = await _pump(tester, size: const Size(900, 1400));
      await tester.runAsync(
        () => _queueTie(repos, [
          (
            'user_figure_shorthands',
            [shorthand('role2s')],
            [shorthand('role1s')],
          ),
        ]),
      );
      await _open(tester);
      expect(find.textContaining('zoom: robins'), findsOneWidget);
      expect(find.textContaining('zoom: larks'), findsOneWidget);
    });

    testWidgets('a dialect\'s name for a figure of your own is shown by the '
        'figure\'s name (#1023)', (tester) async {
      Map<String, Object?> mine(String name) => {
        'name': 'Mine',
        'moves': {userFigureKeyFor('zoom-id'): name},
      };
      final repos = await _pump(
        tester,
        size: const Size(900, 1400),
        seed: (repos) => repos.userGlossary.upsert(
          UserGlossaryEntry(
            id: 'zoom-id',
            kindName: UserGlossaryEntryKind.customFigure.name,
            name: 'role1s zoom',
            definition: 'A zoom.',
            description: 'Fast.',
            payload: const {
              'template': '{move}',
              'defaultBeats': 8,
              'params': <Object?>[],
            },
            createdAt: _tie,
          ),
        ),
      );
      await tester.runAsync(
        () => _queueTie(repos, [
          ('custom_dialects', [mine('whizz')], [mine('swoosh')]),
        ]),
      );
      await _open(tester);
      expect(find.textContaining('larks zoom → whizz'), findsOneWidget);
      expect(find.textContaining('larks zoom → swoosh'), findsOneWidget);
      expect(find.textContaining('userFigure:'), findsNothing);
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
      expect(find.text('This device: circle left 3 places'), findsOneWidget);
      expect(find.text('Another device: star left 4 places'), findsOneWidget);
      expect(find.text('A1'), findsNothing);
    });

    testWidgets('a use of a figure of your own shows the figure\'s current '
        'wording, not the line its dance stored (#1023)', (tester) async {
      await _pump(
        tester,
        size: const Size(400, 1400),
        seed: (repos) async {
          await repos.userGlossary.upsert(
            UserGlossaryEntry(
              id: 'zoom-id',
              kindName: UserGlossaryEntryKind.customFigure.name,
              name: 'zoom',
              definition: 'A zoom.',
              description: 'Fast.',
              payload: {
                'template': '{who} {move} around',
                'defaultBeats': 8,
                'params': [
                  {'key': 'who', 'kind': 'dancerSet'},
                ],
              },
              createdAt: _tie,
            ),
          );
          await _queueDanceTie(
            repos,
            local: [
              userFigureUseFigure(
                id: 'zoom-id',
                args: const {'who': 'role1s'},
                text: 'a stale stored line',
                beats: 8,
              ),
            ],
            remote: [
              Figure(move: 'circle', params: const {'beats': 8}),
            ],
          );
        },
      );
      await tester.pumpAndSettle();
      await _open(tester);

      expect(find.text('This device: larks zoom around'), findsOneWidget);
      expect(find.textContaining('a stale stored line'), findsNothing);
    });
  });

  group('combine both', () {
    testWidgets('is offered for a list, not for a single setting', (
      tester,
    ) async {
      final repos = await _pump(tester, size: const Size(400, 1400));
      await tester.runAsync(
        () => _queueTie(repos, [
          ('theme_mode', 'dark', 'light'),
          (
            'custom_dialects',
            [
              {'name': 'Mine'},
            ],
            [
              {'name': 'Theirs'},
            ],
          ),
        ]),
      );
      await _open(tester);

      expect(
        find.byKey(
          const ValueKey('sync-conflict-option-custom_dialects-combine'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sync-conflict-option-theme_mode-combine')),
        findsNothing,
      );
      expect(find.text('Keeps all 2 items from both devices'), findsOneWidget);
    });

    testWidgets('asks which version to keep of each entry both changed '
        'before it can be saved, then keeps everything', (tester) async {
      final repos = await _pump(tester, size: const Size(400, 1600));
      await tester.runAsync(
        () => _queueTie(repos, [
          (
            'custom_dialects',
            [
              {'name': 'Shared', 'v': 'mine'},
              {'name': 'Mine only'},
            ],
            [
              {'name': 'Shared', 'v': 'theirs'},
              {'name': 'Theirs only'},
            ],
          ),
        ]),
      );
      await _open(tester);

      await tester.tap(find.text('Combine both'));
      await tester.pump();
      FilledButton apply() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('sync-conflict-apply')),
      );
      expect(
        apply().onPressed,
        isNull,
        reason: 'the entry both changed has no choice yet',
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('sync-conflict-entry-Shared')),
          matching: find.text('Another device'),
        ),
      );
      await tester.pump();
      expect(apply().onPressed, isNotNull);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('sync-conflict-apply')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(
        await tester.runAsync(() => repos.settings.get('custom_dialects')),
        [
          {'name': 'Shared', 'v': 'theirs'},
          {'name': 'Mine only'},
          {'name': 'Theirs only'},
        ],
      );
    });

    testWidgets('is unavailable, and says why, when the result would be too '
        'long to keep', (tester) async {
      final repos = await _pump(tester, size: const Size(400, 1400));
      await tester.runAsync(
        () => _queueTie(repos, [
          (
            'custom_dialects',
            [
              for (var i = 0; i < syncMaxCustomDialects; i++) {'name': 'm$i'},
            ],
            [
              {'name': 'theirs'},
            ],
          ),
        ]),
      );
      await _open(tester);

      final combine = tester.widget<RadioListTile<String>>(
        find.byKey(
          const ValueKey('sync-conflict-option-custom_dialects-combine'),
        ),
      );
      expect(combine.enabled, isFalse);
      expect(
        find.text(
          "Can't combine: together these would be 129, and this list holds "
          'at most 128.',
        ),
        findsOneWidget,
      );
    });
  });

  group('undo', () {
    Future<void> saveOtherDevicesTheme(
      WidgetTester tester,
      CompendiumRepositories repos,
    ) async {
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
    }

    testWidgets('the saved prompt is transient: it floats and times out '
        'rather than persisting until dismissed (#463)', (tester) async {
      final repos = await _pump(tester);
      await saveOtherDevicesTheme(tester, repos);

      final snackBar = tester.widget<SnackBar>(
        find.byKey(const ValueKey('sync-conflict-saved')),
      );
      expect(snackBar.persist, isFalse);
      expect(snackBar.behavior, SnackBarBehavior.floating);

      await tester.pump(snackBar.duration);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sync-conflict-saved')), findsNothing);
    });

    testWidgets('reopens the choice with the earlier versions; picking again '
        'saves the new choice', (tester) async {
      final repos = await _pump(tester);
      await saveOtherDevicesTheme(tester, repos);
      expect(
        await tester.runAsync(() => repos.settings.get('theme_mode')),
        'light',
      );
      expect(find.text('Your choices are saved.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sync-conflict-undo')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Choose again between the versions you had. Nothing changes until '
          'you save.',
        ),
        findsOneWidget,
      );
      expect(find.text('dark'), findsOneWidget);
      expect(find.text('light'), findsOneWidget);
      expect(
        await tester.runAsync(() => repos.settings.get('theme_mode')),
        'light',
        reason: 'reopening changes nothing',
      );

      await tester.tap(find.text('This device'));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('sync-conflict-apply')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(
        await tester.runAsync(() => repos.settings.get('theme_mode')),
        'dark',
      );
    });

    testWidgets('closing the reopened choice without picking changes '
        'nothing', (tester) async {
      final repos = await _pump(tester);
      await saveOtherDevicesTheme(tester, repos);

      await tester.tap(find.byKey(const ValueKey('sync-conflict-undo')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sync-conflict-later')));
      await tester.pumpAndSettle();

      expect(
        await tester.runAsync(() => repos.settings.get('theme_mode')),
        'light',
      );
    });
  });

  group('showing every saved detail', () {
    testWidgets('one of the user\'s own figures is compared in the active '
        'dialect, by what it becomes (#709)', (tester) async {
      final compound = canonicalJson(
        CompoundDefinition(
          params: const [],
          figures: [
            testFigure(move: 'swing', params: const {'who': 'partners'}),
          ],
          bindings: const [],
        ).toJson(),
      );
      Map<String, Object?> body(String definition, String payload) => {
        'id': 'g1',
        'kind': 'compound',
        'name': 'role1s spiral',
        'definition': definition,
        'description': 'Round.',
        'keywords': const <String>[],
        'notes': null,
        'payload': payload,
        'createdAt': '2026-09-01T00:00:00.000Z',
      };
      final theirs = SyncRecordBlob(
        kind: SyncRecordKind.glossaryEntry,
        id: 'g1',
        updatedAt: DateTime.utc(2026, 9, 30),
        deletedAt: null,
        existenceAt: DateTime.utc(2026, 9, 30),
        body: body('role2s lead.', '{not json'),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SyncConflictComparison(
                group: SyncConflictGroup(
                  kind: SyncRecordKind.glossaryEntry,
                  recordId: 'g1',
                  localBody: body('role1s lead.', compound),
                  candidates: syncConflictGroupFor(
                    SyncConflictReconsideration(
                      kind: SyncRecordKind.glossaryEntry,
                      recordId: 'g1',
                      before: null,
                      offered: [theirs],
                      writtenWireHash: 'written',
                      writtenAt: DateTime.utc(2026, 9, 30),
                    ),
                  ).candidates,
                ),
                lookups: const SyncConflictLookups(),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Definition'), findsOneWidget);
      expect(find.textContaining('larks lead.'), findsOneWidget);
      expect(find.textContaining('robins lead.'), findsOneWidget);
      expect(find.textContaining('role1s'), findsNothing);
      expect(find.text('What it is'), findsOneWidget);
      expect(find.textContaining('Combination · '), findsOneWidget);
      expect(find.textContaining('swing'), findsOneWidget);
      expect(find.textContaining('Needs repair'), findsOneWidget);
      expect(find.textContaining('{not json'), findsNothing);
    });

    testWidgets('a term, and the figure another device made of it, are '
        'compared by its dance form and its wording (#1023)', (tester) async {
      Map<String, Object?> body(String kind, String payload) => {
        'id': 'g1',
        'kind': kind,
        'name': 'zesty corners',
        'definition': 'A lively turn.',
        'description': 'Corners.',
        'keywords': const <String>[],
        'notes': null,
        'payload': payload,
        'createdAt': '2026-09-01T00:00:00.000Z',
      };
      final figure = canonicalJson(
        UserFigureDefinition(
          form: 'contra',
          template: '{move} with the role1s',
          defaultBeats: 8,
          params: const [],
        ).toJson(),
      );
      final theirs = SyncRecordBlob(
        kind: SyncRecordKind.glossaryEntry,
        id: 'g1',
        updatedAt: DateTime.utc(2026, 9, 30),
        deletedAt: null,
        existenceAt: DateTime.utc(2026, 9, 30),
        body: body('customFigure', figure),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SyncConflictComparison(
                group: SyncConflictGroup(
                  kind: SyncRecordKind.glossaryEntry,
                  recordId: 'g1',
                  localBody: body('term', '{"form":"ecd"}'),
                  candidates: syncConflictGroupFor(
                    SyncConflictReconsideration(
                      kind: SyncRecordKind.glossaryEntry,
                      recordId: 'g1',
                      before: null,
                      offered: [theirs],
                      writtenWireHash: 'written',
                      writtenAt: DateTime.utc(2026, 9, 30),
                    ),
                  ).candidates,
                ),
                lookups: const SyncConflictLookups(),
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('Term · '), findsOneWidget);
      expect(find.textContaining('English (ECD)'), findsOneWidget);
      expect(find.textContaining('New figure · '), findsOneWidget);
      expect(find.textContaining('{move} with the larks'), findsOneWidget);
      expect(find.textContaining('Newer version'), findsNothing);
    });

    testWidgets('a merged-away record a version cites is named as the record '
        'it became', (tester) async {
      final theirs = SyncRecordBlob(
        kind: SyncRecordKind.dance,
        id: 'd1',
        updatedAt: DateTime.utc(2026, 9, 30),
        deletedAt: null,
        existenceAt: DateTime.utc(2026, 9, 30),
        body: {
          'id': 'd1',
          'title': 'Hey Day',
          'customFields': [
            {'fieldId': 'f2', 'value': 'Becket'},
          ],
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SyncConflictComparison(
                group: SyncConflictGroup(
                  kind: SyncRecordKind.dance,
                  recordId: 'd1',
                  localBody: {
                    'id': 'd1',
                    'title': 'Hey Day',
                    'customFields': [
                      {'fieldId': 'f1', 'value': 'Improper'},
                    ],
                  },
                  candidates: syncConflictGroupFor(
                    SyncConflictReconsideration(
                      kind: SyncRecordKind.dance,
                      recordId: 'd1',
                      before: null,
                      offered: [theirs],
                      writtenWireHash: 'written',
                      writtenAt: DateTime.utc(2026, 9, 30),
                    ),
                  ).candidates,
                  aliases: const {
                    SyncRecordKind.customFieldDef: {'f2': 'f1'},
                  },
                ),
                lookups: const SyncConflictLookups(
                  customFields: {'f1': 'Formation note'},
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.textContaining('Formation note: Becket'),
        findsOneWidget,
        reason: 'custom field f2 was merged into f1',
      );
      expect(find.textContaining('Not on this device'), findsNothing);
    });

    for (final (name, kind, id, edit, mine, theirs) in [
      (
        "a tag's colour",
        SyncRecordKind.tag,
        't1',
        (Map<String, Object?> body) => {...body, 'color': 0xFF445566},
        '#112233',
        '#445566',
      ),
      (
        "a venue's sponsor",
        SyncRecordKind.venue,
        'v1',
        (Map<String, Object?> body) => {...body, 'sponsor': 'LCFD'},
        'CDS',
        'LCFD',
      ),
    ]) {
      testWidgets('$name is shown when it is all that changed', (tester) async {
        final repos = await _pump(tester);
        await tester.runAsync(() async {
          expect(
            await repos.tags.upsert(
              Tag(id: 't1', name: 'Easy', color: 0xFF112233),
            ),
            't1',
          );
          await repos.venues.upsert(
            Venue(id: 'v1', name: 'Grange', sponsor: 'CDS'),
          );
          await _queueRecordTie(repos, kind, id, edit);
        });
        await _open(tester);

        expect(find.text('This device: $mine'), findsOneWidget);
        expect(find.text('Another device: $theirs'), findsOneWidget);
        expect(find.textContaining('only in details this view'), findsNothing);
      });
    }

    testWidgets("a program's linked and written venues are shown together", (
      tester,
    ) async {
      final repos = await _pump(tester);
      await tester.runAsync(() async {
        await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
        await repos.venues.upsert(Venue(id: 'v2', name: 'Town Hall'));
        await repos.programs.create(_program(venue: 'upstairs', venueId: 'v1'));
        await _queueRecordTie(
          repos,
          SyncRecordKind.program,
          'p1',
          (body) => {...body, 'venue': 'downstairs', 'venueId': 'v2'},
        );
      });
      await _open(tester);

      expect(find.text('This device: Grange Hall · upstairs'), findsOneWidget);
      expect(
        find.text('Another device: Town Hall · downstairs'),
        findsOneWidget,
      );
    });

    for (final (currency, units, mineText, theirsText) in [
      ('USD', 25050, '250.50 USD', '300.00 USD'),
      ('JPY', 5000, '5000 JPY', '6000 JPY'),
    ]) {
      testWidgets('a program pay in $currency is shown formatted, with its '
          'currency code', (tester) async {
        final repos = await _pump(tester);
        await tester.runAsync(() async {
          await repos.programs.create(
            Program(
              id: 'p1',
              title: 'Friday dance',
              payMinorUnits: units,
              payCurrency: currency,
              createdAt: _tie,
              updatedAt: _tie,
            ),
          );
          await _queueRecordTie(
            repos,
            SyncRecordKind.program,
            'p1',
            (body) => {
              ...body,
              'payMinorUnits': currency == 'JPY' ? 6000 : 30000,
            },
          );
        });
        await _open(tester);

        expect(find.text('This device: $mineText'), findsOneWidget);
        expect(find.text('Another device: $theirsText'), findsOneWidget);
        expect(find.textContaining('25050'), findsNothing);
      });
    }

    testWidgets("a dialect shows the terms that differ, not just its name", (
      tester,
    ) async {
      final repos = await _pump(tester);
      final mine = {
        ...Dialect.larksRobins.toJson(),
        'name': 'Mine',
        'moves': {'swing': 'swing'},
      };
      await tester.runAsync(
        () => _queueTie(repos, [
          (
            'custom_dialects',
            [mine],
            [
              {
                ...mine,
                'moves': {'swing': 'twirl'},
              },
            ],
          ),
        ]),
      );
      await _open(tester);

      expect(find.text('Mine: Move substitutions'), findsOneWidget);
      expect(find.text('This device: swing → swing'), findsOneWidget);
      expect(find.text('Another device: swing → twirl'), findsOneWidget);
    });

    testWidgets('a theme shows the colours that differ', (tester) async {
      final repos = await _pump(tester);
      Map<String, Object?> theme(int primary) => {
        'id': 'th1',
        'name': 'Dusk',
        'brightness': 'dark',
        'roles': {'primary': primary, 'onPrimary': 0xFFFFFFFF},
      };
      await tester.runAsync(
        () => _queueTie(repos, [
          ('custom_themes', [theme(0xFF112233)], [theme(0xFF445566)]),
        ]),
      );
      await _open(tester);

      expect(find.text('Dusk: Primary'), findsOneWidget);
      expect(find.text('This device: #112233'), findsOneWidget);
      expect(find.text('Another device: #445566'), findsOneWidget);
    });

    testWidgets("a figure's note or walkthrough is shown when it is all "
        'that changed', (tester) async {
      final repos = await _pump(tester, size: const Size(400, 1400));
      await tester.runAsync(
        () => _queueDanceTie(
          repos,
          local: [
            Figure(move: 'swing', params: const {'beats': 16}, note: 'gently'),
            Figure(move: 'circle', params: const {'beats': 8}),
          ],
          remote: [
            Figure(move: 'swing', params: const {'beats': 16}, note: 'firmly'),
            Figure(
              move: 'circle',
              params: const {'beats': 8},
              walkthroughOverride: 'Circle all the way',
            ),
          ],
        ),
      );
      await _open(tester);

      expect(find.textContaining('note: gently'), findsOneWidget);
      expect(find.textContaining('note: firmly'), findsOneWidget);
      expect(
        find.textContaining('walkthrough: Circle all the way'),
        findsOneWidget,
      );
    });

    testWidgets('slots are matched by dance and by repeat, not by title', (
      tester,
    ) async {
      final repos = await _pump(tester);
      await tester.runAsync(() async {
        await repos.dances.create(_dance('a', title: 'Chorus Jig'));
        await repos.dances.create(_dance('b', title: 'Chorus Jig'));
        await repos.dances.create(_dance('c', title: 'Rory'));
        await repos.programs.create(
          _program(
            slots: [
              ProgramSlot(id: 's0', position: 0, danceId: 'a'),
              ProgramSlot(id: 's1', position: 1, danceId: 'c'),
              ProgramSlot(id: 's2', position: 2, danceId: 'c'),
            ],
          ),
        );
        await _queueRecordTie(
          repos,
          SyncRecordKind.program,
          'p1',
          (body) => {
            ...body,
            'slots': [_slot(0, danceId: 'b'), _slot(1, danceId: 'c')],
          },
        );
      });
      await _open(tester);

      // The other device's "Chorus Jig" is a different dance; it also has
      // one "Rory" where this device has two.
      expect(find.text('Only on this device'), findsOneWidget);
      expect(find.text('Only on the other device'), findsOneWidget);
      expect(find.text('Chorus Jig'), findsNWidgets(2));
      expect(find.text('Rory'), findsOneWidget);
      expect(find.text('The same dances, in a different order.'), findsNothing);
    });

    testWidgets('a timing change is not reported as a reorder', (tester) async {
      final repos = await _pump(tester);
      await tester.runAsync(() async {
        await repos.dances.create(_dance('a', title: 'Chorus Jig'));
        await repos.programs.create(
          _program(
            slots: [ProgramSlot(id: 's0', position: 0, danceId: 'a')],
          ),
        );
        await _queueRecordTie(
          repos,
          SyncRecordKind.program,
          'p1',
          (body) => {
            ...body,
            'slots': [_slot(0, danceId: 'a', minutes: 12)],
          },
        );
      });
      await _open(tester);

      expect(find.text('The same dances, in a different order.'), findsNothing);
      expect(
        find.text(
          'The same dances, with different details such as timings or '
          'alternates.',
        ),
        findsOneWidget,
      );
    });

    testWidgets("a citation's page and a link's destination, kind and group "
        'are shown', (tester) async {
      final repos = await _pump(tester, size: const Size(400, 1400));
      await tester.runAsync(() async {
        await repos.publishedSources.upsert(
          PublishedSource(id: 'src', title: 'Zesty Contras'),
        );
        await repos.dances.create(_dance('rel', title: 'Rory'));
        await repos.dances.create(
          _dance(
            'd1',
            sourceCitations: [SourceCitation(sourceId: 'src', page: '12')],
            links: [
              DanceLink(
                id: 'l1',
                kind: LinkKind.video,
                url: 'https://a.example/v',
                label: 'Teaching video',
              ),
              DanceLink(
                id: 'l2',
                kind: LinkKind.relatedDance,
                targetDanceId: 'rel',
              ),
            ],
          ),
        );
        await _queueRecordTie(repos, SyncRecordKind.dance, 'd1', (body) {
          return {
            ...body,
            'sourceCitations': [
              {'sourceId': 'src', 'page': '42'},
            ],
            'links': [
              {
                'id': 'l1',
                'kind': 'source',
                'url': 'https://b.example/v',
                'label': 'Teaching video',
              },
              {
                'id': 'l2',
                'kind': 'relatedDance',
                'targetDanceId': 'rel',
                'transitive': true,
              },
            ],
          };
        });
      });
      await _open(tester);

      expect(find.text('This device: Zesty Contras, p. 12'), findsOneWidget);
      expect(find.text('Another device: Zesty Contras, p. 42'), findsOneWidget);
      expect(
        find.text(
          'This device: video · Teaching video · https://a.example/v; '
          'link · Rory',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Another device: source link · Teaching video · '
          'https://b.example/v; link · Rory · in the related-dance group',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an event date is the day the program names, in any time '
        'zone', (tester) async {
      final repos = await _pump(tester);
      await tester.runAsync(() async {
        await repos.programs.create(
          _program(eventDate: DateTime.utc(2026, 10, 5)),
        );
        await _queueRecordTie(
          repos,
          SyncRecordKind.program,
          'p1',
          (body) => {...body, 'eventDate': '2026-10-06T00:00:00.000Z'},
        );
      });
      await _open(tester);

      expect(find.text('This device: Oct 5, 2026'), findsOneWidget);
      expect(find.text('Another device: Oct 6, 2026'), findsOneWidget);
    });

    test('a calendar date reads the same day west of Greenwich', () {
      // A stored midnight-UTC date is read by its UTC fields, so no time
      // zone can move it to the day before.
      final day = syncConflictCalendarDate('2026-10-05T00:00:00.000Z');
      expect((day.year, day.month, day.day), (2026, 10, 5));
    });
  });
}
