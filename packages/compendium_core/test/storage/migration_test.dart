// Migration tests, per the convention documented on [CompendiumDatabase]:
// every schema migration ships a test that opens a fixture DB captured at the
// previous version and asserts the migration behaves.
//
// Coverage starts at [kMinSupportedSchemaVersion], not at v1. Schema versions
// below the floor were retired (#837, floor since raised to v35) along with
// their `onUpgrade` steps, fixtures and dumps, so there is nothing left to
// migrate from; a below-floor database is refused outright, which
// `schema_floor_test.dart` covers.
//
// No binary fixtures remain (the floor raise to v35 retired every one). Each
// upgrade is exercised from its `drift_schemas/` dump instead
// (`GeneratedHelper`), which carries structure only; the test seeds the rows
// it needs.
//
// Schema *shape* after migration is covered separately by
// `schema_verification_test.dart` (#828); this file covers data semantics.
import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/storage/database.dart'
    show
        callersBoxRollAwayRoleRepairDoneKey,
        chainHandBackfillDoneKey,
        compactDosidoSeesawCanonicalRebuildDoneKey,
        gripSingleFileCanonicalInclusionDoneKey,
        inversePairNormalisationDoneKey,
        modifierContainerCanonicalRebuildDoneKey,
        promenadeTurnCircleWordingCanonicalRebuildDoneKey,
        purgeCorruptionRepairDoneKey,
        sectionRuleVersionKey,
        starPromenadeHandRemovalDoneKey,
        taxonomyV33CanonicalRebuildDoneKey,
        taxonomyV34CanonicalRebuildDoneKey,
        taxonomyV35FigureNormalizationDoneKey,
        kSectionRuleVersion;
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

import 'generated/schema.dart';
import '../figures_support.dart';

void main() {
  test('v35 review rows retain legacy null local hashes at v36', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    addTearDown(raw.close);

    final historical = GeneratedHelper().databaseForVersion(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      35,
    );
    await historical.customSelect('SELECT 1').get();
    await historical.customStatement(
      'INSERT INTO review_queue '
      '(kind, record_id, counterpart_id, reason, candidate_blob, '
      'candidate_hash, queued_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        'tag',
        'legacy-local',
        'legacy-remote',
        'baselineAbsenceTombstone',
        '{"id":"legacy-remote"}',
        'candidate-hash',
        1,
      ],
    );
    await historical.close();

    final migrated = CompendiumDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    addTearDown(migrated.close);
    await migrated.customSelect('SELECT 1').get();

    final row = await migrated
        .customSelect(
          'SELECT local_hash FROM review_queue '
          'WHERE kind = ? AND record_id = ? AND counterpart_id = ?',
          variables: [
            Variable.withString('tag'),
            Variable.withString('legacy-local'),
            Variable.withString('legacy-remote'),
          ],
        )
        .getSingle();
    expect(row.read<String?>('local_hash'), isNull);
  });

  group('re-homed migration-agnostic tests (from the retired v11 group)', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compendium_core_mig_v35_');
      dbPath = p.join(dir.path, 'test.sqlite');
      // Build a floor-version file from its schema snapshot, then drop
      // `dance_fts` so `beforeOpen` repairs it and durably sets
      // [derivedRebuildRequiredKey] — the marker these tests rely on. (Every
      // surviving `onUpgrade` step leaves the derived tables alone, so the
      // retired v22 step is no longer what sets it.)
      final historical = GeneratedHelper().databaseForVersion(
        NativeDatabase(File(dbPath)),
        kMinSupportedSchemaVersion,
      );
      await historical.customSelect('SELECT 1').get();
      await historical.customStatement('DROP TABLE dance_fts');
      await historical.close();
    });

    tearDown(() => dir.delete(recursive: true));

    // Re-homed from the retired v11 group (#837, floor raised to v35). The
    // property is not specific to any start version: it asserts that a
    // *failed* derived rebuild is not memoized, so the next `ensureMigrated`
    // retries rather than treating the failure as done. The marker it relies
    // on is set by `beforeOpen` when an FTS table is missing (see `setUp`).
    test('ensureMigrated retries after a failed rebuild', () async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = _FailingOnceRepositories(db, contraTaxonomy);

      // First attempt: beforeOpen sets the durable marker, then the rebuild
      // throws. The failure must propagate and NOT be cached.
      await expectLater(repos.ensureMigrated(), throwsA(isA<StateError>()));
      expect(repos.rebuildAttempts, 1);

      // Marker still set — the rebuild did not complete.
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(marker, isNotEmpty);

      // Second attempt: the memo was cleared, so it retries and now succeeds.
      await repos.ensureMigrated();
      expect(repos.rebuildAttempts, 2);
      final cleared = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable.withString(derivedRebuildRequiredKey)],
          )
          .get();
      expect(
        cleared,
        isEmpty,
        reason: 'a successful retry must clear the durable marker',
      );

      await db.close();
    });

    // Also re-homed from the retired v11 group (#837, floor raised to v35).
    test('ensureMigrated with both derivedRebuildRequired and sectionRuleVersion '
        'pending performs exactly one rebuild', () async {
      // Guard for the alreadyRebuilt optimisation (#844): when derivedRebuildRequired
      // fires, the rebuild uses current labelForFigure code and already produces
      // correct section values. _recomputeSectionLabelsIfNeeded must not run a
      // second byte-identical pass — it doubles the startup cost for users
      // upgrading from a schema that also sets derivedRebuildRequired.
      //
      // Falsification target: remove the alreadyRebuilt guard in _runMigration
      // (pass alreadyRebuilt: false unconditionally) and this test goes red.
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = _CountingRepositories(db, contraTaxonomy);

      // The floor file is missing dance_fts → beforeOpen sets
      // derivedRebuildRequiredKey. sectionRuleVersionKey is absent (fresh
      // snapshot, never run).
      await repos.ensureMigrated();

      expect(
        repos.rebuildAttempts,
        1,
        reason:
            'derivedRebuildRequired and sectionRuleVersion pending together '
            'must produce exactly one rebuild, not two',
      );

      // Key is written so subsequent opens skip the sweep entirely.
      final key = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ? AND value_json = ?',
            variables: [
              Variable.withString(sectionRuleVersionKey),
              Variable.withString('"$kSectionRuleVersion"'),
            ],
          )
          .get();
      expect(key, isNotEmpty, reason: 'sectionRuleVersionKey must be written');

      await db.close();
    });
  });

  group('taxonomy v33 canonical rebuild', () {
    test(
      'normalizes legacy assumed subjects and refreshes effective defaults',
      () async {
        final db = CompendiumDatabase(NativeDatabase.memory());
        final repos = CompendiumRepositories(db, contraTaxonomy);
        addTearDown(db.close);

        await repos.dances.create(
          Dance(
            id: 'v33-canonical',
            title: 'v33 canonical',
            figures: [
              Figure(
                move: 'box_circulate',
                params: {'who': 'partners'},
                assumedSubject: true,
              ),
              Figure(move: 'figure_8'),
              Figure(move: 'box_circulate', params: {'who': 'partners'}),
            ],
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );

        final beforeJson =
            (await db
                    .customSelect(
                      'SELECT figures_json FROM dances WHERE id = ?',
                      variables: [Variable.withString('v33-canonical')],
                    )
                    .getSingle())
                .read<String>('figures_json');
        expect(beforeJson, contains('"assumedSubject":true'));
        expect(beforeJson, contains('"who":"partners"'));
        for (final key in [
          purgeCorruptionRepairDoneKey,
          inversePairNormalisationDoneKey,
          starPromenadeHandRemovalDoneKey,
          gripSingleFileCanonicalInclusionDoneKey,
          promenadeTurnCircleWordingCanonicalRebuildDoneKey,
          compactDosidoSeesawCanonicalRebuildDoneKey,
          modifierContainerCanonicalRebuildDoneKey,
          chainHandBackfillDoneKey,
        ]) {
          await repos.settings.set(key, 'done');
        }
        await repos.settings.set(sectionRuleVersionKey, kSectionRuleVersion);
        await db.customUpdate(
          'UPDATE dance_figures SET canonical_text = CASE idx '
          'WHEN 0 THEN ? WHEN 1 THEN ? WHEN 2 THEN ? END WHERE dance_id = ?',
          variables: [
            Variable.withString('partners box circulate'),
            Variable.withString('ones figure 8 half'),
            Variable.withString('partners box circulate'),
            Variable.withString('v33-canonical'),
          ],
          updates: {db.danceFigures},
        );
        await db.customUpdate(
          'UPDATE dance_fts SET figures_text = ? WHERE dance_id = ?',
          variables: [
            Variable.withString(
              'partners box circulate ones figure 8 half partners box circulate',
            ),
            Variable.withString('v33-canonical'),
          ],
        );
        final marker = await db
            .customSelect(
              'SELECT 1 FROM settings WHERE key = ?',
              variables: [
                Variable.withString(taxonomyV33CanonicalRebuildDoneKey),
              ],
            )
            .get();
        expect(marker, isEmpty);

        await repos.ensureMigrated();

        final rows = await db
            .customSelect(
              'SELECT idx, canonical_text FROM dance_figures '
              'WHERE dance_id = ? ORDER BY idx',
              variables: [Variable.withString('v33-canonical')],
            )
            .get();
        expect(rows.map((row) => row.read<String>('canonical_text')).toList(), [
          'role2s box circulate',
          'ones half figure 8',
          'partners box circulate',
        ]);
        final fts = await db
            .customSelect(
              'SELECT figures_text FROM dance_fts WHERE dance_id = ?',
              variables: [Variable.withString('v33-canonical')],
            )
            .getSingle();
        expect(
          fts.read<String>('figures_text'),
          'role2s box circulate ones half figure 8 partners box circulate',
        );
        final afterJson =
            (await db
                    .customSelect(
                      'SELECT figures_json FROM dances WHERE id = ?',
                      variables: [Variable.withString('v33-canonical')],
                    )
                    .getSingle())
                .read<String>('figures_json');
        expect(afterJson, isNot(beforeJson));
        expect(afterJson, isNot(contains('"assumedSubject":true')));
        expect(afterJson, contains('"who":"partners"'));

        final completed = await db
            .customSelect(
              'SELECT value_json FROM settings WHERE key = ?',
              variables: [
                Variable.withString(taxonomyV33CanonicalRebuildDoneKey),
              ],
            )
            .getSingle();
        expect(completed.read<String>('value_json'), '"done"');
      },
    );
  });

  group('taxonomy v34 mad robin canonical rebuild', () {
    test(
      'normalizes assumed TCB subjects and retries safely after interruption',
      () async {
        final db = CompendiumDatabase(NativeDatabase.memory());
        final repos = _FailingOnceRepositories(db, contraTaxonomy);
        addTearDown(db.close);

        final legacyFigures = [
          Figure(
            move: 'mad_robin',
            params: const {'direction': 'clockwise', 'whom': 'neighbors'},
            assumedSubject: true,
          ),
          Figure.meanwhile(
            figures: [
              Figure(
                move: 'mad_robin',
                params: const {
                  'direction': 'counterclockwise',
                  'whom': 'partners',
                },
                assumedSubject: true,
              ),
              Figure(
                move: 'swing',
                params: const {'who': 'partners', 'beats': 16},
              ),
            ],
            beats: 8,
          ),
          Figure(
            move: 'mad_robin',
            params: const {
              'who': 'ones',
              'direction': 'clockwise',
              'whom': 'partners',
            },
            assumedSubject: true,
          ),
        ];
        await repos.dances.create(
          Dance(
            id: 'v34-canonical',
            title: 'v34 canonical',
            figures: legacyFigures,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
        // Seed the pre-v34 persisted shape below the repository write
        // convergence point. This keeps the test focused on ensureMigrated's
        // source rewrite and retry-safe rebuild rather than the later ingress
        // guard.
        await db.customUpdate(
          'UPDATE dances SET figures_json = ? WHERE id = ?',
          variables: [
            Variable<String>(encodeFigures(legacyFigures)),
            Variable<String>('v34-canonical'),
          ],
          updates: {db.dances},
        );
        final legacy = await db
            .customSelect(
              'SELECT figures_json FROM dances WHERE id = ?',
              variables: [Variable<String>('v34-canonical')],
            )
            .getSingle();
        final legacyFirst =
            (jsonDecode(legacy.read<String>('figures_json')) as List<dynamic>)
                    .first
                as Map<String, dynamic>;
        expect(
          (legacyFirst['params'] as Map<String, dynamic>).containsKey('who'),
          isFalse,
        );
        expect(legacyFirst['assumedSubject'], isTrue);

        for (final key in [
          purgeCorruptionRepairDoneKey,
          inversePairNormalisationDoneKey,
          starPromenadeHandRemovalDoneKey,
          gripSingleFileCanonicalInclusionDoneKey,
          promenadeTurnCircleWordingCanonicalRebuildDoneKey,
          compactDosidoSeesawCanonicalRebuildDoneKey,
          chainHandBackfillDoneKey,
          taxonomyV33CanonicalRebuildDoneKey,
        ]) {
          await repos.settings.set(key, 'done');
        }
        await repos.settings.set(sectionRuleVersionKey, kSectionRuleVersion);

        await db.customUpdate(
          'UPDATE dance_figures SET canonical_text = ? WHERE dance_id = ?',
          variables: [
            Variable<String>('stale canonical'),
            Variable<String>('v34-canonical'),
          ],
          updates: {db.danceFigures},
        );
        await db.customUpdate(
          'UPDATE dance_fts SET figures_text = ? WHERE dance_id = ?',
          variables: [
            Variable<String>('stale figures'),
            Variable<String>('v34-canonical'),
          ],
        );

        await expectLater(repos.ensureMigrated(), throwsA(isA<StateError>()));
        expect(repos.rebuildAttempts, 1);

        final rewritten = await db
            .customSelect(
              'SELECT figures_json FROM dances WHERE id = ?',
              variables: [Variable<String>('v34-canonical')],
            )
            .getSingle();
        final rewrittenFigures =
            jsonDecode(rewritten.read<String>('figures_json')) as List<dynamic>;
        final rewrittenFirst = rewrittenFigures[0] as Map<String, dynamic>;
        final rewrittenMeanwhile = rewrittenFigures[1] as Map<String, dynamic>;
        final rewrittenMeanwhileParams =
            rewrittenMeanwhile['params'] as Map<String, dynamic>;
        final rewrittenNested =
            (rewrittenMeanwhileParams['figures'] as List<dynamic>)[0]
                as Map<String, dynamic>;
        final rewrittenExplicit = rewrittenFigures[2] as Map<String, dynamic>;
        expect(
          (rewrittenFirst['params'] as Map<String, dynamic>)['who'],
          ParamVocab.unspecified,
        );
        expect(rewrittenFirst.containsKey('assumedSubject'), isFalse);
        expect(
          (rewrittenNested['params'] as Map<String, dynamic>)['who'],
          ParamVocab.unspecified,
        );
        expect(rewrittenNested.containsKey('assumedSubject'), isFalse);
        expect(
          (rewrittenExplicit['params'] as Map<String, dynamic>)['who'],
          'ones',
        );
        expect(rewrittenExplicit['assumedSubject'], isTrue);
        final pendingRebuild = await db
            .customSelect(
              'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
              variables: [Variable<String>(derivedRebuildRequiredKey)],
            )
            .get();
        expect(pendingRebuild, isNotEmpty);
        final incomplete = await db
            .customSelect(
              'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
              variables: [Variable<String>(taxonomyV34CanonicalRebuildDoneKey)],
            )
            .get();
        expect(incomplete, isEmpty);

        await repos.ensureMigrated();
        expect(repos.rebuildAttempts, 2);

        final dance = (await repos.dances.getById('v34-canonical'))!;
        final expectedCanonical = [
          'mad robin once clockwise neighbors',
          'mad robin once counterclockwise partners',
          'partners swing',
          'ones mad robin once clockwise partners',
        ];
        final rows = await db
            .customSelect(
              'SELECT canonical_text FROM dance_figures '
              'WHERE dance_id = ? ORDER BY idx',
              variables: [Variable<String>('v34-canonical')],
            )
            .get();
        expect(
          rows.map((row) => row.read<String>('canonical_text')).toList(),
          expectedCanonical,
        );
        final expectedFts = [
          expectedCanonical[0],
          'mad robin once counterclockwise partners meanwhile partners swing',
          expectedCanonical[1],
          expectedCanonical[2],
          expectedCanonical[3],
        ].join(' ');
        final fts = await db
            .customSelect(
              'SELECT figures_text FROM dance_fts WHERE dance_id = ?',
              variables: [Variable<String>('v34-canonical')],
            )
            .getSingle();
        expect(fts.read<String>('figures_text'), expectedFts);
        final pendingAfterRetry = await db
            .customSelect(
              'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',
              variables: [Variable<String>(derivedRebuildRequiredKey)],
            )
            .get();
        expect(pendingAfterRetry, isEmpty);
        final completed = await db
            .customSelect(
              'SELECT value_json FROM settings WHERE key = ? AND deleted_at IS NULL',
              variables: [Variable<String>(taxonomyV34CanonicalRebuildDoneKey)],
            )
            .getSingle();
        expect(completed.read<String>('value_json'), '"done"');
        expect(figuresOf(dance).first.params['who'], ParamVocab.unspecified);
        expect(
          figuresOf(dance)[1].subFigures.first.params['who'],
          ParamVocab.unspecified,
        );
        expect(figuresOf(dance)[2].params['who'], 'ones');
        expect(figuresOf(dance)[2].assumedSubject, isTrue);
      },
    );
  });

  group('modifier container canonical rebuild', () {
    test(
      'refreshes structural canonical and FTS text once when marker is absent',
      () async {
        final db = CompendiumDatabase(NativeDatabase.memory());
        final repos = _CountingRepositories(db, contraTaxonomy);
        addTearDown(db.close);

        final figure = Figure.modifier(
          figures: [
            Figure(move: 'swing'),
            Figure.meanwhile(
              figures: [
                Figure(move: 'petronella'),
                Figure(move: 'circle'),
              ],
              beats: 8,
            ),
          ],
          beats: 8,
        );
        await repos.dances.create(
          Dance(
            id: 'modifier-canonical-rebuild',
            title: 'Modifier canonical rebuild',
            figures: [figure],
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
        await _markPre1192SweepsComplete(repos);
        await repos.settings.remove(modifierContainerCanonicalRebuildDoneKey);
        await db.customUpdate(
          'UPDATE dance_figures SET canonical_text = ? WHERE dance_id = ?',
          variables: [
            Variable<String>('stale canonical'),
            Variable<String>('modifier-canonical-rebuild'),
          ],
        );
        await db.customUpdate(
          'UPDATE dance_fts SET figures_text = ? WHERE dance_id = ?',
          variables: [
            Variable<String>('stale FTS'),
            Variable<String>('modifier-canonical-rebuild'),
          ],
        );

        final expected = FigureRenderer(contraTaxonomy).renderCanonical(figure);
        await repos.ensureMigrated();

        final indexed = await db
            .customSelect(
              'SELECT canonical_text FROM dance_figures WHERE dance_id = ?',
              variables: [Variable<String>('modifier-canonical-rebuild')],
            )
            .get();
        expect(
          indexed.map((row) => row.read<String>('canonical_text')),
          containsAll(['partners swing', 'petronella', 'circle left 4 places']),
        );
        final fts = await db
            .customSelect(
              'SELECT figures_text FROM dance_fts WHERE dance_id = ?',
              variables: [Variable<String>('modifier-canonical-rebuild')],
            )
            .getSingle();
        expect(fts.read<String>('figures_text'), contains(expected));

        final marker = await db
            .customSelect(
              'SELECT value_json FROM settings WHERE key = ? '
              'AND deleted_at IS NULL',
              variables: [
                Variable<String>(modifierContainerCanonicalRebuildDoneKey),
              ],
            )
            .getSingle();
        expect(marker.read<String>('value_json'), '"done"');

        final rebuilds = repos.rebuildAttempts;
        await repos.ensureMigrated();
        expect(repos.rebuildAttempts, rebuilds);
      },
    );
  });

  group('taxonomy v35 figure normalization', () {
    // invalid-fixture: these figures deliberately use the pre-v35 persisted vocabulary
    test('rewrites legacy keys and nested structural figures', () async {
      final db = CompendiumDatabase(NativeDatabase.memory());
      final repos = CompendiumRepositories(db, contraTaxonomy);
      addTearDown(db.close);

      final legacyFigures = [
        Figure(
          move: 'pull_by_dancers',
          params: const {'who': 'partners', 'hand': 'left'},
        ),
        Figure.meanwhile(
          figures: [
            Figure(move: 'circle', params: const {'turn': 'left', 'beats': 8}),
            Figure(move: 'swing'),
          ],
          beats: 8,
        ),
        Figure.modifier(
          figures: [
            Figure(
              move: 'pull_by_dancers',
              params: const {'who': 'partners', 'hand': 'left'},
            ),
            Figure.meanwhile(
              figures: [
                Figure(
                  move: 'circle',
                  params: const {'turn': 'left', 'beats': 8},
                ),
                Figure(move: 'swing'),
              ],
              beats: 8,
            ),
          ],
          beats: 8,
        ),
      ];
      await repos.dances.create(
        Dance(
          id: 'v35-normalization',
          title: 'v35 normalization',
          figures: legacyFigures,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await db.customUpdate(
        'UPDATE dances SET figures_json = ? WHERE id = ?',
        variables: [
          Variable<String>(encodeFigures(legacyFigures)),
          Variable<String>('v35-normalization'),
        ],
        updates: {db.dances},
      );
      await repos.settings.set(taxonomyV35FigureNormalizationDoneKey, 'false');

      await repos.ensureMigrated();

      final dance = (await repos.dances.getById('v35-normalization'))!;
      expect(figuresOf(dance)[0].move, 'pull_by');
      expect(figuresOf(dance)[0].params, {'who': 'partners', 'hand': 'left'});
      final circle = figuresOf(
        dance,
      )[1].subFigures.firstWhere((figure) => figure.move == 'circle');
      expect(circle.params['direction'], 'left');
      expect(circle.params.containsKey('turn'), isFalse);
      final modifier = figuresOf(dance)[2];
      expect(modifier.subFigures.first.move, 'pull_by');
      final nestedCircle = modifier.subFigures[1].subFigures.first;
      expect(nestedCircle.params['direction'], 'left');
      expect(nestedCircle.params.containsKey('turn'), isFalse);
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [
              Variable.withString(taxonomyV35FigureNormalizationDoneKey),
            ],
          )
          .getSingle();
      expect(marker.read<String>('value_json'), 'true');
    });

    // invalid-fixture: this exercises a v35 database that predates the taxonomy migration marker
    test('runs when the taxonomy marker is absent', () async {
      final db = CompendiumDatabase(NativeDatabase.memory());
      final repos = CompendiumRepositories(db, contraTaxonomy);
      addTearDown(db.close);

      final legacyFigures = [
        Figure(
          move: 'pull_by_dancers',
          params: const {'who': 'partners', 'hand': 'left'},
        ),
        Figure(move: 'circle', params: const {'turn': 'left'}),
      ];
      await repos.dances.create(
        Dance(
          id: 'v35-absent-marker',
          title: 'v35 absent marker',
          figures: legacyFigures,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await db.customUpdate(
        'UPDATE dances SET figures_json = ? WHERE id = ?',
        variables: [
          Variable<String>(encodeFigures(legacyFigures)),
          Variable<String>('v35-absent-marker'),
        ],
        updates: {db.dances},
      );

      await repos.ensureMigrated();

      final dance = (await repos.dances.getById('v35-absent-marker'))!;
      expect(figuresOf(dance).first.move, 'pull_by');
      expect(figuresOf(dance)[1].params, {'direction': 'left'});
      final marker = await db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ? AND deleted_at IS NULL',
            variables: [
              Variable.withString(taxonomyV35FigureNormalizationDoneKey),
            ],
          )
          .getSingle();
      expect(marker.read<String>('value_json'), 'true');
    });
  });

  group('purge-corruption repair (#429/#466)', () {
    test(
      'ensureMigrated removes legacy corrupt rows once and marks it done',
      () async {
        final db = CompendiumDatabase(NativeDatabase.memory());
        final repos = CompendiumRepositories(db, contraTaxonomy);
        addTearDown(db.close);

        // A healthy dance + a program whose slot references it, plus a VALID
        // owner->target relatedDance link (both dances present) that the
        // destructive repair sweep must PRESERVE.
        await repos.dances.create(
          Dance(
            id: 'd-target',
            title: 'Target Dance',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
        await repos.dances.create(
          Dance(
            id: 'd-ok',
            title: 'Good Dance',
            links: [
              DanceLink(
                id: 'l-good',
                kind: LinkKind.relatedDance,
                targetDanceId: 'd-target',
              ),
            ],
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
        await repos.programs.create(
          Program(
            id: 'p1',
            title: 'Set',
            slots: [ProgramSlot(id: 's-ok', position: 0, danceId: 'd-ok')],
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );

        // Inject the two row shapes a pre-fix hard purge would have left: a
        // (danceId, text)-both-null slot (#429) and a relatedDance link whose
        // target was SET NULL (#466). Written raw so they bypass the domain
        // guards, exactly like a legacy on-disk database.
        await db.customStatement(
          'INSERT INTO program_slots (id, program_id, position, dance_id, '
          'text, is_alt) VALUES (?, ?, ?, NULL, NULL, 0)',
          ['s-bad', 'p1', 1],
        );
        await db.customStatement(
          'INSERT INTO dance_links (id, dance_id, kind, target_dance_id) '
          'VALUES (?, ?, ?, NULL)',
          ['l-bad', 'd-ok', LinkKind.relatedDance.name],
        );

        await repos.ensureMigrated();

        // The corrupt rows are gone; the healthy rows — including the VALID
        // relatedDance link — survive untouched (the sweep is not over-eager).
        final slots = await db
            .customSelect('SELECT id FROM program_slots ORDER BY id')
            .get();
        expect(slots.map((r) => r.read<String>('id')), ['s-ok']);
        final links = await db
            .customSelect('SELECT id FROM dance_links ORDER BY id')
            .get();
        expect(links.map((r) => r.read<String>('id')), ['l-good']);

        // Loads succeed after the repair, and the valid link still hydrates.
        final programs = await repos.programs.listAll();
        expect(programs.single.slots.single.danceId, 'd-ok');
        final loadedDances = await repos.dances.listAll();
        expect(loadedDances, hasLength(2));
        final owner = loadedDances.firstWhere((d) => d.id == 'd-ok');
        expect(owner.links.single.id, 'l-good');
        expect(owner.links.single.targetDanceId, 'd-target');

        // The database is referentially clean and its FTS index is a perfect
        // 1:1 mirror of `dances`. We compare the ORDERED id multisets (not just
        // row counts): dance_fts.dance_id is an unconstrained FTS column, so a
        // count-only check would pass even if one dance were missing while
        // another had a duplicate row. Comparing sorted id lists catches
        // missing, orphaned, and duplicated FTS rows alike.
        final fkViolations = await db
            .customSelect('PRAGMA foreign_key_check')
            .get();
        expect(fkViolations, isEmpty, reason: 'no dangling FKs after repair');
        final ftsIds =
            (await db
                    .customSelect(
                      'SELECT dance_id FROM dance_fts ORDER BY dance_id',
                    )
                    .get())
                .map((r) => r.read<String>('dance_id'))
                .toList();
        final danceIds =
            (await db.customSelect('SELECT id FROM dances ORDER BY id').get())
                .map((r) => r.read<String>('id'))
                .toList();
        expect(
          ftsIds,
          danceIds,
          reason: 'dance_fts must be an exact 1:1 mirror of dances',
        );

        // The one-shot marker is durably recorded.
        final marker = await db
            .customSelect(
              'SELECT value_json FROM settings WHERE key = ?',
              variables: [Variable.withString(purgeCorruptionRepairDoneKey)],
            )
            .get();
        expect(marker, hasLength(1));
      },
    );

    test('skips the repair when the done-marker is already set', () async {
      final db = CompendiumDatabase(NativeDatabase.memory());
      final repos = CompendiumRepositories(db, contraTaxonomy);
      addTearDown(db.close);

      // Pre-stamp the marker (this first statement also triggers onCreate), so
      // a later corrupt row must be left alone — the sweep runs at most once.
      await db.customStatement(
        'INSERT OR REPLACE INTO settings (key, value_json) VALUES (?, ?)',
        [purgeCorruptionRepairDoneKey, 'true'],
      );
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Set',
          slots: [ProgramSlot(id: 's-ok', position: 0, text: 'Waltz')],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await db.customStatement(
        'INSERT INTO program_slots (id, program_id, position, dance_id, text, '
        'is_alt) VALUES (?, ?, ?, NULL, NULL, 0)',
        ['s-bad', 'p1', 1],
      );

      await repos.ensureMigrated();

      final slots = await db
          .customSelect('SELECT id FROM program_slots ORDER BY id')
          .get();
      expect(slots.map((r) => r.read<String>('id')), ['s-bad', 's-ok']);
    });
  });

  group('CallersBox roll-away role repair (#1192)', () {
    test(
      'repairs only exact legacy figures and preserves dance metadata',
      () async {
        final db = CompendiumDatabase(NativeDatabase.memory());
        final repos = CompendiumRepositories(db, contraTaxonomy);
        addTearDown(db.close);

        final meanwhile = Figure.meanwhile(
          beats: 8,
          extraParams: {'preserve': 'container metadata'},
          figures: [
            Figure(
              move: 'roll_away',
              params: {'who': 'neighbors', 'beats': 4},
              note: 'role2s roll right, role1s side-step left',
            ),
            Figure(move: 'figure_8', note: 'untouched sibling'),
          ],
        );
        final affected = _rollAwayDance(
          id: 'callersbox-affected',
          figures: [
            Figure(
              move: 'roll_away',
              params: {'who': 'partners', 'beats': 4},
              note: 'role1s roll left, role2s step aside right',
            ),
            meanwhile,
          ],
          provenance: Provenance(
            source: ProvenanceSource.callersbox,
            externalId: 'affected',
            importedAt: DateTime.utc(2024),
          ),
        );
        final nonCallersBox = _rollAwayDance(
          id: 'other-source',
          figures: [
            Figure(
              move: 'roll_away',
              params: {'who': 'neighbors'},
              note: 'role1s roll right, role2s side-step left',
            ),
          ],
          provenance: Provenance(
            source: ProvenanceSource.json,
            importedAt: DateTime.utc(2024),
          ),
        );
        final absentProvenance = _rollAwayDance(
          id: 'no-provenance',
          figures: [
            Figure(
              move: 'roll_away',
              params: {'who': 'neighbors'},
              note: 'role1s roll right, role2s side-step left',
            ),
          ],
        );
        final alreadyCorrect = _rollAwayDance(
          id: 'already-correct',
          figures: [
            Figure(
              move: 'roll_away',
              params: {'who': 'role1s', 'whom': 'neighbors'},
              note: 'role1s roll right, role2s side-step left',
            ),
          ],
          provenance: _callersBoxProvenance('already-correct'),
        );
        final divergentNote = _rollAwayDance(
          id: 'divergent-note',
          figures: [
            Figure(
              move: 'roll_away',
              params: {'who': 'neighbors'},
              note: 'role1s roll right; role2s side-step left',
            ),
          ],
          provenance: _callersBoxProvenance('divergent-note'),
        );
        final unsupportedRelationship = _rollAwayDance(
          id: 'unsupported-relationship',
          figures: [
            Figure(
              move: 'roll_away',
              params: {'who': 'ones'},
              note: 'role1s roll right, role2s side-step left',
            ),
          ],
          provenance: _callersBoxProvenance('unsupported-relationship'),
        );
        final assumedSubject = _rollAwayDance(
          id: 'assumed-subject',
          figures: [
            Figure(
              move: 'roll_away',
              params: {'who': 'neighbors'},
              note: 'role1s roll right, role2s side-step left',
              assumedSubject: true,
            ),
          ],
          provenance: _callersBoxProvenance('assumed-subject'),
        );
        final softDeleted = _rollAwayDance(
          id: 'soft-deleted',
          figures: [
            Figure(
              move: 'roll_away',
              params: {'who': 'neighbors'},
              note: 'role1s roll right, role2s side-step left',
            ),
          ],
          provenance: _callersBoxProvenance('soft-deleted'),
          deletedAt: DateTime.utc(2024, 1, 2),
        );

        for (final dance in [
          affected,
          nonCallersBox,
          absentProvenance,
          alreadyCorrect,
          divergentNote,
          unsupportedRelationship,
          assumedSubject,
          softDeleted,
        ]) {
          await repos.dances.create(dance);
        }
        await _markPre1192SweepsComplete(repos);

        await repos.ensureMigrated();

        final repaired = await repos.dances.getById(affected.id);
        expect(repaired!.callingNotes, affected.callingNotes);
        expect(repaired.rating, affected.rating);
        expect(figuresOf(repaired)[0].params, {
          'who': 'role2s',
          'whom': 'partners',
          'beats': 4,
        });
        final repairedMeanwhile = figuresOf(repaired)[1];
        expect(repairedMeanwhile.params['preserve'], 'container metadata');
        expect(repairedMeanwhile.subFigures[0].params, {
          'who': 'role1s',
          'whom': 'neighbors',
          'beats': 4,
        });
        expect(repairedMeanwhile.subFigures[1].note, 'untouched sibling');

        for (final id in [
          nonCallersBox.id,
          absentProvenance.id,
          alreadyCorrect.id,
          divergentNote.id,
          unsupportedRelationship.id,
          assumedSubject.id,
        ]) {
          final unchanged = await repos.dances.getById(id);
          expect(
            figuresOf(unchanged!),
            figuresOf(
              ([
                nonCallersBox,
                absentProvenance,
                alreadyCorrect,
                divergentNote,
                unsupportedRelationship,
                assumedSubject,
              ].firstWhere((dance) => dance.id == id)),
            ),
            reason: '$id must not match the legacy repair predicate',
          );
        }
        final deleted = await repos.dances.getById(
          softDeleted.id,
          includeDeleted: true,
        );
        expect(figuresOf(deleted!).single.params, {
          'who': 'role2s',
          'whom': 'neighbors',
        });

        for (final table in ['dance_fts', 'dance_substring_fts']) {
          final indexed = await db
              .customSelect(
                'SELECT figures_text FROM $table WHERE dance_id = ?',
                variables: [Variable.withString(affected.id)],
              )
              .getSingle();
          expect(indexed.read<String>('figures_text'), contains('role1s'));
          expect(indexed.read<String>('figures_text'), contains('partners'));
        }

        final marker = await db
            .customSelect(
              'SELECT 1 FROM settings WHERE key = ?',
              variables: [
                Variable.withString(callersBoxRollAwayRoleRepairDoneKey),
              ],
            )
            .get();
        expect(marker, isNotEmpty);
      },
    );

    test(
      'commits source rewrite and retries derived rebuild after failure',
      () async {
        final db = CompendiumDatabase(NativeDatabase.memory());
        final dance = _rollAwayDance(
          id: 'callersbox-retry',
          figures: [
            Figure(
              move: 'roll_away',
              params: {'who': 'neighbors'},
              note: 'role1s roll right, role2s side-step left',
            ),
          ],
          provenance: _callersBoxProvenance('retry'),
        );
        final setup = CompendiumRepositories(db, contraTaxonomy);
        await setup.dances.create(dance);
        await _markPre1192SweepsComplete(setup);
        final repos = _FailingOnceRepositories(db, contraTaxonomy);
        addTearDown(db.close);

        await expectLater(repos.ensureMigrated(), throwsA(isA<StateError>()));
        expect(repos.rebuildAttempts, 1);
        final failedSource = await db
            .customSelect(
              'SELECT figures_json FROM dances WHERE id = ?',
              variables: [Variable.withString(dance.id)],
            )
            .getSingle();
        expect(
          failedSource.read<String>('figures_json'),
          contains('"whom":"neighbors"'),
        );
        expect(
          await db
              .customSelect(
                'SELECT 1 FROM settings WHERE key = ?',
                variables: [Variable.withString(derivedRebuildRequiredKey)],
              )
              .get(),
          isNotEmpty,
        );
        expect(
          await db
              .customSelect(
                'SELECT 1 FROM settings WHERE key = ?',
                variables: [
                  Variable.withString(callersBoxRollAwayRoleRepairDoneKey),
                ],
              )
              .get(),
          isEmpty,
        );

        await repos.ensureMigrated();
        expect(repos.rebuildAttempts, 2);
        expect(
          await db
              .customSelect(
                'SELECT 1 FROM settings WHERE key = ?',
                variables: [Variable.withString(derivedRebuildRequiredKey)],
              )
              .get(),
          isEmpty,
        );
        expect(
          await db
              .customSelect(
                'SELECT 1 FROM settings WHERE key = ?',
                variables: [
                  Variable.withString(callersBoxRollAwayRoleRepairDoneKey),
                ],
              )
              .get(),
          isNotEmpty,
        );
      },
    );
  });

  group('v36 -> v37 upgrade (issue #1554 programs.dialect_name)', () {
    test(
      'adds a nullable dialect_name and keeps legacy program rows',
      () async {
        final raw = sqlite3.sqlite3.openInMemory();
        final historical = GeneratedHelper().databaseForVersion(
          NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
          36,
        );
        await historical.customSelect('SELECT 1').get();
        final before = await historical
            .customSelect("PRAGMA table_info('programs')")
            .get();
        expect(
          before.map((row) => row.read<String>('name')),
          isNot(contains('dialect_name')),
        );
        await historical.customStatement(
          "INSERT INTO programs "
          "(id, title, notes, status, hide_alternates, created_at, updated_at) "
          "VALUES ('legacy-program', 'Legacy', 'keep', 'draft', 1, 0, 0)",
        );
        await historical.close();

        final db = CompendiumDatabase(
          NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
        );
        addTearDown(() async {
          await db.close();
          raw.close();
        });
        await db.customSelect('SELECT 1').get();

        final columns = await db
            .customSelect("PRAGMA table_info('programs')")
            .get();
        final dialect = columns.singleWhere(
          (row) => row.read<String>('name') == 'dialect_name',
        );
        expect(dialect.read<int>('notnull'), 0, reason: 'must be nullable');

        final row = await db
            .customSelect(
              'SELECT title, notes, hide_alternates, dialect_name '
              "FROM programs WHERE id = 'legacy-program'",
            )
            .getSingle();
        expect(row.read<String>('title'), 'Legacy');
        expect(row.read<String>('notes'), 'keep');
        expect(row.read<int>('hide_alternates'), 1);
        expect(row.read<String?>('dialect_name'), isNull);
      },
    );
  });

  group('v37 -> v38 upgrade (issue #1418 programs.pay_*)', () {
    test('adds nullable pay columns and keeps legacy program rows', () async {
      final raw = sqlite3.sqlite3.openInMemory();
      final historical = GeneratedHelper().databaseForVersion(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
        37,
      );
      await historical.customSelect('SELECT 1').get();
      final before = await historical
          .customSelect("PRAGMA table_info('programs')")
          .get();
      final beforeNames = before.map((row) => row.read<String>('name'));
      expect(beforeNames, isNot(contains('pay_minor_units')));
      expect(beforeNames, isNot(contains('pay_currency')));
      await historical.customStatement(
        "INSERT INTO programs "
        "(id, title, notes, status, hide_alternates, created_at, updated_at) "
        "VALUES ('legacy-program', 'Legacy', 'keep', 'draft', 1, 0, 0)",
      );
      await historical.close();

      final db = CompendiumDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      addTearDown(() async {
        await db.close();
        raw.close();
      });
      await db.customSelect('SELECT 1').get();

      final columns = await db
          .customSelect("PRAGMA table_info('programs')")
          .get();
      for (final name in ['pay_minor_units', 'pay_currency']) {
        final column = columns.singleWhere(
          (row) => row.read<String>('name') == name,
        );
        expect(column.read<int>('notnull'), 0, reason: '$name nullable');
      }

      final row = await db
          .customSelect(
            'SELECT title, notes, hide_alternates, pay_minor_units, '
            "pay_currency FROM programs WHERE id = 'legacy-program'",
          )
          .getSingle();
      expect(row.read<String>('title'), 'Legacy');
      expect(row.read<String>('notes'), 'keep');
      expect(row.read<int>('hide_alternates'), 1);
      expect(row.read<int?>('pay_minor_units'), isNull);
      expect(row.read<String?>('pay_currency'), isNull);
    });
  });
}

Dance _rollAwayDance({
  required String id,
  required List<Figure> figures,
  Provenance? provenance,
  DateTime? deletedAt,
}) => Dance(
  id: id,
  title: id,
  figures: figures,
  provenance: provenance,
  callingNotes: 'preserve this dance metadata',
  rating: 4,
  createdAt: DateTime.utc(2024),
  updatedAt: DateTime.utc(2024),
  deletedAt: deletedAt,
);

Provenance _callersBoxProvenance(String externalId) => Provenance(
  source: ProvenanceSource.callersbox,
  externalId: externalId,
  importedAt: DateTime.utc(2024),
);

Future<void> _markPre1192SweepsComplete(CompendiumRepositories repos) async {
  for (final key in [
    purgeCorruptionRepairDoneKey,
    inversePairNormalisationDoneKey,
    starPromenadeHandRemovalDoneKey,
    gripSingleFileCanonicalInclusionDoneKey,
    promenadeTurnCircleWordingCanonicalRebuildDoneKey,
    compactDosidoSeesawCanonicalRebuildDoneKey,
    taxonomyV33CanonicalRebuildDoneKey,
    taxonomyV34CanonicalRebuildDoneKey,
    modifierContainerCanonicalRebuildDoneKey,
    chainHandBackfillDoneKey,
  ]) {
    await repos.settings.set(key, 'done');
  }
  await repos.settings.set(sectionRuleVersionKey, kSectionRuleVersion);
  await repos.settings.set(taxonomyV35FigureNormalizationDoneKey, true);
}

/// A [CompendiumRepositories] whose derived-index rebuild throws on its first
/// invocation and succeeds thereafter — used to prove [ensureMigrated] retries
/// after a transient failure rather than caching it.
class _FailingOnceRepositories extends CompendiumRepositories {
  _FailingOnceRepositories(super.db, super.taxonomy);

  int rebuildAttempts = 0;

  @override
  Future<void> runDerivedRebuild({
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    rebuildAttempts++;
    if (rebuildAttempts == 1) {
      throw StateError('injected rebuild failure');
    }
    await super.runDerivedRebuild(onProgress: onProgress);
  }
}

/// Counts [runDerivedRebuild] calls without interfering with the real rebuild.
class _CountingRepositories extends CompendiumRepositories {
  _CountingRepositories(super.db, super.taxonomy);

  int rebuildAttempts = 0;

  @override
  Future<void> runDerivedRebuild({
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    rebuildAttempts++;
    await super.runDerivedRebuild(onProgress: onProgress);
  }
}
