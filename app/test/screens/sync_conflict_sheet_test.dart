import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/sync_conflict_details.dart';
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
  group('showing every saved detail', () {
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
