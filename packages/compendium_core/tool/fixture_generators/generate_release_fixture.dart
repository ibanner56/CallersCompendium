// Generates a representative database using the code of a REAL release, to be
// committed as `test/storage/fixtures/vN.sqlite` (N = the schema that release
// wrote). Read by `test/storage/real_release_fixture_test.dart`.
//
// THIS FILE IS NOT BUILT OR ANALYSED WITH THE REPOSITORY. It is written against
// the public API of the release it is run on (v0.4.0-beta for v35), which is
// not the API at head; `analysis_options.yaml` excludes this directory for that
// reason. Run it from a checkout of the release tag, never from head.
//
// Recipe (v35 from v0.4.0-beta, commit 04ab10c7; kCompendiumSchemaVersion = 35;
// v38 is the same recipe from v0.6.0-beta, commit a6d52290, whose package has no
// `resolution: workspace` line to delete):
//
//   git worktree add --detach <dir> v0.4.0-beta
//   cd <dir>/packages/compendium_core
//   # standalone resolution at the tag (drops `resolution: workspace` and the
//   # dev-only dependencies that need the workspace to resolve)
//   sed -i '/^resolution: workspace/d; /^  analyzer:/d; /^  build_runner:/d; /^  drift_dev:/d' pubspec.yaml
//   dart pub get
//   cp <repo>/packages/compendium_core/tool/fixture_generators/generate_release_fixture.dart tool/
//   dart run tool/generate_release_fixture.dart <out>/v35.sqlite
//
// The output is byte-reproducible: every timestamp the script writes is fixed,
// and the one the release's own seeder takes from the wall clock (the default
// difficulty levels) is pinned below. Two runs on the same sqlite3 build produce
// the same sha256; the committed digests are recorded in docs/design/storage.md.
//
// Why a real release and not the schema snapshots: `GeneratedHelper` carries
// structure only, so a test built on it can never notice that `onUpgrade`
// destroyed or mangled the rows, FTS content, links or settings markers a
// shipped database really holds.
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

Future<void> main(List<String> args) async {
  final out = File(args.single);
  if (out.existsSync()) out.deleteSync();
  final t0 = DateTime.utc(2026, 8, 1, 12);

  final db = CompendiumDatabase(NativeDatabase(out));
  final repos = CompendiumRepositories(db, contraTaxonomy);
  // Real startup path: seeds markers exactly as the shipped app would.
  await repos.ensureMigrated();

  await repos.choreographers.upsert(
    Choreographer(
      id: 'c-gaudet',
      name: 'Gaudet, Ted',
      website: 'https://example.org/ted',
      notes: 'Café notes',
      location: 'Boston',
    ),
    at: t0,
  );
  await repos.choreographers.upsert(
    Choreographer(id: 'c-old', name: 'Old Timer', deceased: true),
    at: t0,
  );
  await repos.tags.upsert(
    Tag(id: 't-beginner', name: 'Beginner', color: 0xFF336699),
    at: t0,
  );
  await repos.tags.upsert(
    Tag(id: 't-gender-free', name: 'Gender-free'),
    at: t0,
  );
  await repos.publishedSources.upsert(
    PublishedSource(
      id: 'ps-1',
      title: 'Zesty Contras',
      author: 'Larry Jennings',
      year: 1983,
    ),
    at: t0,
  );
  final field = CustomFieldDef(
    id: 'cf-energy',
    key: 'energy',
    label: 'Energy',
    type: CustomFieldType.choice,
    choices: ['low', 'medium', 'high'],
    showInList: true,
  );
  await repos.customFieldDefs.upsert(field, at: t0);
  await repos.venues.upsert(
    Venue(
      id: 'v-grange',
      name: 'Grange Hall',
      city: 'Lexington',
      stateProv: 'MA',
      contact1Name: 'Pat Booker',
      contact1Email: 'pat@example.org',
    ),
    at: t0,
  );

  // B: minimal manual dance, no figures.
  await repos.dances.create(
    Dance(id: 'd-plain', title: 'Plain Dance', createdAt: t0, updatedAt: t0),
  );
  // A: ordinary contra with every relation populated.
  await repos.dances.create(
    Dance(
      id: 'd-chase',
      title: 'Chase the Squirrel',
      authorIds: ['c-gaudet'],
      figures: [
        Figure(move: 'balance', params: const {'who': 'neighbors'}),
        Figure(move: 'swing', params: const {'who': 'neighbors', 'beats': 8}),
        Figure(move: 'circle', params: const {'direction': 'left', 'beats': 8}),
        Figure.meanwhile(
          figures: [
            Figure(move: 'swing', params: const {'who': 'partners'}),
            Figure(move: 'balance', params: const {'who': 'partners'}),
          ],
          beats: 8,
        ),
      ],
      hook: 'Squirrel hook with café — diacritics',
      callingNotes: 'Teach the swing carefully.',
      walkthrough: 'Walk it twice.',
      rating: 4,
      tunes: ['Rakish Paddy', 'Cuckoo\'s Nest'],
      customFields: [CustomFieldValue(fieldId: 'cf-energy', value: 'high')],
      tagIds: ['t-beginner', 't-gender-free'],
      links: [
        DanceLink(
          id: 'l-1',
          kind: LinkKind.video,
          url: 'https://example.org/v',
          label: 'Demo',
        ),
        DanceLink(
          id: 'l-2',
          kind: LinkKind.relatedDance,
          targetDanceId: 'd-plain',
          transitive: true,
        ),
      ],
      sourceCitations: [
        SourceCitation(sourceId: 'ps-1', page: '12', number: 'A1'),
      ],
      provenance: Provenance(
        source: ProvenanceSource.callersbox,
        externalId: 'cb-4242',
        importedAt: t0,
        permission: 'full',
        license: 'CC-BY',
        sourceVersion: '2026-07',
      ),
      createdAt: t0,
      updatedAt: t0,
    ),
  );
  // C: soft-deleted dance (tombstone).
  await repos.dances.create(
    Dance(
      id: 'd-gone',
      title: 'Deleted Dance',
      figures: [
        Figure(move: 'swing', params: const {'who': 'partners'}),
      ],
      createdAt: t0,
      updatedAt: t0,
      deletedAt: t0,
    ),
  );
  // D: dance whose title/figures text exercises FTS tokenisation.
  await repos.dances.create(
    Dance(
      id: 'd-fts',
      title: 'Résumé Reel',
      figures: [
        Figure(move: 'robins_chain', params: const {'who': 'neighbors'}),
      ],
      hook: 'hey for four',
      createdAt: t0,
      updatedAt: t0,
    ),
  );

  await repos.programs.create(
    Program(
      id: 'p-spring',
      title: 'Spring Dance 2026',
      eventDate: DateTime.utc(2026, 3, 15),
      venue: 'Grange Hall',
      venueId: 'v-grange',
      caller: 'Alex Caller',
      band: 'The Reelers',
      dancerLevel: 'mixed',
      notes: 'bring snacks',
      slots: [
        ProgramSlot(
          id: 's-1',
          position: 0,
          danceId: 'd-chase',
          walkthroughMinutes: 5,
          danceMinutes: 12,
        ),
        ProgramSlot(id: 's-2', position: 1, text: 'Break / waltz'),
        ProgramSlot(
          id: 's-3',
          position: 2,
          danceId: 'd-plain',
          isAlt: true,
          guestCaller: 'Sam',
        ),
      ],
      createdAt: t0,
      updatedAt: t0,
    ),
  );

  await repos.settings.set('ui.theme', 'dark', at: t0);
  await repos.settings.set('ui.sort', {'by': 'title', 'asc': true}, at: t0);

  await db.close();

  final raw = sqlite3.sqlite3.open(out.path);
  // The v0.4.0-beta seeder stamps the difficulty levels with the wall clock.
  // Pin them so regenerating yields identical bytes.
  final pinned = t0.millisecondsSinceEpoch ~/ 1000;
  raw.execute(
    'UPDATE difficulty_levels SET updated_at = $pinned, existence_at = $pinned',
  );
  // Fold the WAL into the main file so the artefact is a single file.
  raw.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  final v = raw.select('PRAGMA user_version').first.columnAt(0);
  stdout.writeln('user_version=$v');
  for (final t in [
    'dances',
    'dance_figures',
    'dance_fts',
    'dance_substring_fts',
    'programs',
    'program_slots',
    'settings',
    'tags',
    'dance_tags',
    'venues',
    'choreographers',
    'custom_field_values',
    'dance_links',
    'dance_tunes',
    'dance_source_citations',
  ]) {
    try {
      final n = raw.select('SELECT count(*) FROM $t').first.columnAt(0);
      stdout.writeln('$t: $n');
    } catch (e) {
      stdout.writeln('$t: (n/a: $e)');
    }
  }
  raw.execute('VACUUM');
  raw.close();
  stdout.writeln('size=${out.lengthSync()} bytes');
}
