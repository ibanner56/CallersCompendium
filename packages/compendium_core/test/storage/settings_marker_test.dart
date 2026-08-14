// The migration control markers in `settings`, and why they must not be
// readable as present once tombstoned (issue #898).
//
// `settings` became soft-deletable in schema v25, and this table also holds
// four internal markers that `CompendiumRepositories.ensureMigrated` reads with
// raw SQL to decide whether a one-time repair still needs to run. Three of them
// are "done" markers, where a marker wrongly read as present **skips a repair
// permanently** — for `purgeCorruptionRepairDoneKey` that repair is the one
// that removes rows which otherwise throw on load and take down the whole
// Programs / Collection listing (#429, #466). That is a far nastier failure
// than a stale row, so it is proved here rather than reasoned about.
//
// THE ROUTE IS ORDINARY CODE, NOT A HYPOTHETICAL. `isBackupEligibleSettingKey`
// in `app/lib/src/data/backup_service.dart` denylists eight named keys plus the
// `editor_draft:` / `program_editor_draft:` prefixes; none of the four markers
// is on either list. So `_applyAppSettings` calls `SettingsRepository.remove`
// on any marker that exists locally but is absent from the backup being
// restored — exactly what a backup taken before that marker was written looks
// like. Before v25 that was harmless: the marker hard-deleted, read as absent,
// and the idempotent repair simply re-ran. The `deleted_at IS NULL` filters on
// those raw reads are what keep it harmless now.
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  /// Tombstones [key] the way a backup restore does — through the repository,
  /// not with a raw DELETE — and asserts the row really is still on disk, so a
  /// test that "passes" because the row vanished is impossible.
  Future<void> tombstoneMarker(
    CompendiumRepositories repos,
    String key,
    Object? value,
  ) async {
    await repos.settings.set(key, value);
    await repos.settings.remove(key);
    final rows = await db
        .customSelect(
          'SELECT deleted_at FROM settings WHERE key = ?',
          variables: [Variable.withString(key)],
        )
        .get();
    expect(
      rows,
      hasLength(1),
      reason: '$key must still be on disk as a tombstone, not erased',
    );
    expect(rows.single.data['deleted_at'], isNotNull, reason: key);
  }

  /// Inserts a `program_slots` row nulled to `(danceId, text) = (null, null)` —
  /// the #429 corruption the one-time repair removes.
  Future<void> seedPurgeCorruption(CompendiumRepositories repos) async {
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
  }

  Future<List<String>> slotIds() async {
    final rows = await db
        .customSelect('SELECT id FROM program_slots ORDER BY id')
        .get();
    return [for (final r in rows) r.read<String>('id')];
  }

  test('a tombstoned purge-repair marker does NOT skip the repair', () async {
    final repos = CompendiumRepositories(db, contraTaxonomy);
    await tombstoneMarker(repos, purgeCorruptionRepairDoneKey, true);
    await seedPurgeCorruption(repos);

    await repos.ensureMigrated();

    expect(
      await slotIds(),
      ['s-ok'],
      reason:
          'the tombstoned marker must read as absent, so the one-time repair '
          'runs; reading it as present would strand a row that throws on load',
    );
  });

  test('a LIVE purge-repair marker still skips the repair', () async {
    // The other half of the pair. Without this, a filter that accidentally
    // matched nothing at all would pass the test above while silently
    // re-running a one-shot sweep on every open.
    final repos = CompendiumRepositories(db, contraTaxonomy);
    await repos.settings.set(purgeCorruptionRepairDoneKey, true);
    await seedPurgeCorruption(repos);

    await repos.ensureMigrated();

    expect(await slotIds(), [
      's-bad',
      's-ok',
    ], reason: 'a live marker means the sweep has already run');
  });

  test('a tombstoned section-rule marker does NOT skip the recompute', () async {
    final repos = _CountingRepositories(db, contraTaxonomy);
    await tombstoneMarker(repos, sectionRuleVersionKey, kSectionRuleVersion);
    // Take the other two one-time passes out of the picture so the rebuild
    // count attributes to the section recompute alone.
    await repos.settings.set(inversePairNormalisationDoneKey, 'done');

    await repos.ensureMigrated();

    expect(
      repos.rebuildAttempts,
      greaterThan(0),
      reason: 'a tombstoned done-marker must not suppress the recompute',
    );
    // ...and the marker is written back live afterwards, so the next open skips.
    expect(
      await repos.settings.get(sectionRuleVersionKey),
      kSectionRuleVersion,
    );
  });

  test(
    'a tombstoned inverse-pair marker does NOT skip the normalisation',
    () async {
      final repos = _CountingRepositories(db, contraTaxonomy);
      await tombstoneMarker(repos, inversePairNormalisationDoneKey, 'done');
      await repos.settings.set(sectionRuleVersionKey, kSectionRuleVersion);

      await repos.ensureMigrated();

      expect(repos.rebuildAttempts, greaterThan(0));
      expect(await repos.settings.get(inversePairNormalisationDoneKey), 'done');
    },
  );

  test('a tombstoned star-promenade marker does NOT skip the strip', () async {
    // Added by #885 (taxonomy v26) after this PR's filters were written, and it
    // arrived without one — the read was `WHERE key = ?` with no
    // `deleted_at IS NULL`. The two PRs never touched the same line, so nothing
    // conflicted; the collision is on the *contract*, because #898 changed what
    // a settings row means and #885 added a new reader of one.
    final repos = _CountingRepositories(db, contraTaxonomy);
    await tombstoneMarker(repos, starPromenadeHandRemovalDoneKey, 'done');
    await repos.settings.set(sectionRuleVersionKey, kSectionRuleVersion);
    await repos.settings.set(inversePairNormalisationDoneKey, 'done');

    await repos.ensureMigrated();

    expect(
      repos.rebuildAttempts,
      greaterThan(0),
      reason: 'a tombstoned done-marker must not suppress the strip',
    );
    expect(await repos.settings.get(starPromenadeHandRemovalDoneKey), 'done');
  });

  test(
    'a tombstoned chain-hand-backfill marker does NOT skip the backfill',
    () async {
      // Same class of hazard as the star-promenade marker above, added later
      // (#976, taxonomy v28): a marker wrongly read as present would leave a
      // bare `role1s`/`role2s` chain imported before this release permanently
      // missing its `hand` in structured search, even after a backup restore
      // clears the marker to force a re-run.
      final repos = _CountingRepositories(db, contraTaxonomy);
      await repos.dances.create(
        Dance(
          id: 'd-chain',
          title: 'Chain Dance',
          figures: [
            Figure(move: 'chain', params: {'who': 'role2s', 'beats': 8}),
          ],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await tombstoneMarker(repos, chainHandBackfillDoneKey, 'done');
      await repos.settings.set(sectionRuleVersionKey, kSectionRuleVersion);
      await repos.settings.set(inversePairNormalisationDoneKey, 'done');
      await repos.settings.set(starPromenadeHandRemovalDoneKey, 'done');
      await repos.settings.set(gripSingleFileCanonicalInclusionDoneKey, 'done');

      await repos.ensureMigrated();

      final reloaded = await repos.dances.getById('d-chain');
      expect(
        reloaded!.figures.single.params['hand'],
        'right',
        reason:
            'a tombstoned done-marker must not suppress the backfill, or the '
            'bare role2s chain stays permanently un-searchable by hand',
      );
      expect(await repos.settings.get(chainHandBackfillDoneKey), 'done');
      expect(
        repos.rebuildAttempts,
        greaterThan(0),
        reason:
            'the backfill rewrites figures_json, which stales the derived '
            'params_json projection (danceIdsWithFigure queries exactly '
            'move+params_json), so a rebuild is owed on that ground alone',
      );
    },
  );

  test(
    'the chain-hand backfill still rebuilds when an EARLIER sweep already '
    'triggered one this call (#976)',
    () async {
      // The hazard: _backfillChainHandIfNeeded ran
      // `!alreadyRebuilt && rewroteAny` in an earlier draft, so when some
      // OTHER sweep (section-label recompute here) already rebuilt earlier
      // in the SAME ensureMigrated call, the chain backfill's own rewrite
      // was silently un-rebuilt — that earlier rebuild ran against the OLD
      // figures_json, before this pass's write. A bare
      // `rebuildAttempts > 0` assertion (as in the sibling test above)
      // cannot see this: the section-label sweep alone already makes it
      // true. Count attempts instead: exactly one for the section-label
      // sweep, and a SECOND, independent one for the chain backfill's own
      // rewrite.
      final repos = _CountingRepositories(db, contraTaxonomy);
      await repos.dances.create(
        Dance(
          id: 'd-chain-both-owed',
          title: 'Chain Dance',
          figures: [
            Figure(move: 'chain', params: {'who': 'role2s', 'beats': 8}),
          ],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      // Force the section-label recompute to run (and rebuild) first...
      await tombstoneMarker(repos, sectionRuleVersionKey, kSectionRuleVersion);
      // ...while the chain backfill ALSO has real work to do.
      await tombstoneMarker(repos, chainHandBackfillDoneKey, 'done');
      await repos.settings.set(inversePairNormalisationDoneKey, 'done');
      await repos.settings.set(starPromenadeHandRemovalDoneKey, 'done');
      await repos.settings.set(gripSingleFileCanonicalInclusionDoneKey, 'done');

      await repos.ensureMigrated();

      final reloaded = await repos.dances.getById('d-chain-both-owed');
      expect(reloaded!.figures.single.params['hand'], 'right');
      expect(
        repos.rebuildAttempts,
        2,
        reason:
            'the section-label sweep rebuilds once; the chain backfill '
            "rewrote a row too, and that row's staleness isn't covered by "
            "a rebuild that ran before the backfill's own write existed — "
            'it must trigger its own, independent rebuild',
      );
    },
  );

  test('the chain-hand backfill leaves a role-less chain untouched (#976 '
      '§6.1.3)', () async {
    // The role→side reading is decoding what the role word already
    // states (#976 §6.1.2) — it is NOT valid for a chain whose `who` is
    // unset, because there the effective `who` comes from the taxonomy
    // DEFAULT, not from anything the source said. Populating `hand` there
    // would derive it from OUR default rather than the data.
    final repos = _CountingRepositories(db, contraTaxonomy);
    await repos.dances.create(
      Dance(
        id: 'd-chain-roleless',
        title: 'Roleless Chain Dance',
        figures: [
          Figure(move: 'chain', params: {'beats': 8}),
        ],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    await tombstoneMarker(repos, chainHandBackfillDoneKey, 'done');
    await repos.settings.set(sectionRuleVersionKey, kSectionRuleVersion);
    await repos.settings.set(inversePairNormalisationDoneKey, 'done');
    await repos.settings.set(starPromenadeHandRemovalDoneKey, 'done');
    await repos.settings.set(gripSingleFileCanonicalInclusionDoneKey, 'done');

    await repos.ensureMigrated();

    final reloaded = await repos.dances.getById('d-chain-roleless');
    expect(
      reloaded!.figures.single.params.containsKey('hand'),
      isFalse,
      reason:
          'a chain with no stored who has no role word to decode a hand '
          'from, so the backfill must leave it alone',
    );
  });

  test(
    'a tombstoned rebuild-required marker is not treated as work owed',
    () async {
      // Opposite polarity to the three above: here *present* means "a rebuild is
      // owed". Pin every other one-time pass live so this marker is the only
      // thing that could trigger a rebuild, then assert none happens.
      final repos = _CountingRepositories(db, contraTaxonomy);
      await tombstoneMarker(repos, derivedRebuildRequiredKey, 'true');
      await repos.settings.set(sectionRuleVersionKey, kSectionRuleVersion);
      await repos.settings.set(inversePairNormalisationDoneKey, 'done');
      await repos.settings.set(starPromenadeHandRemovalDoneKey, 'done');
      await repos.settings.set(gripSingleFileCanonicalInclusionDoneKey, 'done');
      await repos.settings.set(chainHandBackfillDoneKey, 'done');

      await repos.ensureMigrated();

      expect(
        repos.rebuildAttempts,
        0,
        reason:
            'a removed rebuild marker must not resurrect as owed work on every '
            'open',
      );
    },
  );
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
