// Generates `test/storage/fixtures/v41.sqlite`: a database written by the REAL
// `v0.10.0-beta` release (commit 311eca4e, schema 41, contra taxonomy v39), the
// release nearly every upgrading user is on. Read by
// `test/storage/real_release_fixture_test.dart`.
//
// A second generator rather than a branch of `generate_release_fixture.dart`:
// that one is written against v0.8.0-beta's API and must stay runnable at that
// tag to reproduce the committed `v40.sqlite`, and this one uses API v0.8.0-beta
// does not have (program pay, container titles, figure params of taxonomy
// v38/v39). One file holding both would not compile at either tag.
//
// The v40 fixture covers the schema steps from the floor and the rows every
// release writes. This one covers the DATA only v0.9.x and v0.10.0 could
// write, which no schema snapshot and no v0.8 database can hold: the figures
// and params of taxonomy v38 and v39 (long lines and forward and back, a
// figure 8 and poussette `amount`, a double figure 8, hey for three,
// starburst, trade the wave, the third and fourth couples' dancers, third
// corners and opposites, an unstated circle distance, container titles), pass
// by and pass through as the separate moves they were before today's taxonomy
// v40 merged them, English and square dances, program pay, and glossary
// entries and a figure note holding figures.
//
// THIS FILE IS NOT BUILT OR ANALYSED WITH THE REPOSITORY. It is written against
// the public API of v0.10.0-beta, which is not the API at head;
// `analysis_options.yaml` excludes this directory for that reason. Run it from
// a checkout of the release tag, never from head:
//
//   git worktree add --detach <dir> v0.10.0-beta
//   cd <dir>/packages/compendium_core
//   # standalone resolution at the tag (drops `resolution: workspace` and the
//   # dev-only dependencies that need the workspace to resolve)
//   sed -i '/^resolution: workspace/d; /^  analyzer:/d; /^  build_runner:/d; /^  drift_dev:/d' pubspec.yaml
//   dart pub get
//   cp <repo>/packages/compendium_core/tool/fixture_generators/generate_release_fixture_v41.dart tool/
//   dart run tool/generate_release_fixture_v41.dart <out>/v41.sqlite
//
// The output is byte-reproducible: every timestamp the script writes is fixed,
// and the ones the release's own startup takes from the wall clock (the default
// difficulty levels) are pinned below. Two runs on the same sqlite3 build
// produce the same sha256; the committed digest is recorded in
// docs/design/storage.md.
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

Future<void> main(List<String> args) async {
  final out = File(args.single);
  if (out.existsSync()) out.deleteSync();
  final t0 = DateTime.utc(2026, 11, 20, 12);

  final db = CompendiumDatabase(NativeDatabase(out));
  final repos = CompendiumRepositories(db, contraTaxonomy);
  // Real startup path: seeds markers exactly as the shipped app would.
  await repos.ensureMigrated();

  await repos.choreographers.upsert(
    Choreographer(id: 'c-kaynor', name: 'Kaynor, Bob'),
    at: t0,
  );
  await repos.venues.upsert(
    Venue(
      id: 'v-hall',
      name: 'Town Hall',
      address1: '1 Main St',
      city: 'Greenfield',
      stateProv: 'MA',
      country: 'US',
      sponsor: 'Friends of Contra',
      price: r'$12',
      contact2Name: 'Robin Hood',
      contact2Phone: '555-0100',
    ),
    at: t0,
  );

  // A: contra, one figure of every kind taxonomy v38 and v39 added, plus both
  // passes as the separate moves they were at this release.
  await repos.dances.create(
    Dance(
      id: 'd-v10',
      title: 'Eights and Passes',
      authorIds: ['c-kaynor'],
      figures: [
        // v39: long lines became an alias of forward and back; stored as
        // `long_lines`.
        Figure(move: 'long_lines', params: const {'beats': 8}),
        Figure(
          move: 'forward_and_back',
          params: const {
            'formation': 'linesOfThree',
            'goBack': false,
            'beats': 4,
          },
        ),
        // v39: an `other` fraction with its amount, and a double figure 8.
        Figure(
          move: 'figure_8',
          params: const {
            'who': 'ones',
            'where': 'below',
            'lead': 'onesRole1',
            'fraction': 'other',
            'amount': 1.5,
            'double': true,
            'beats': 24,
          },
        ),
        Figure(
          move: 'poussette',
          params: const {
            'who': 'role2s',
            'whom': 'partners',
            'fraction': 'other',
            'amount': 1.25,
            'direction': 'counterclockwise',
          },
        ),
        // v39: hey for three, with the third and fourth couples' dancers.
        Figure(
          move: 'hey_for_three',
          params: const {
            'who': 'threesRole1',
            'whom': 'foursRole2',
            'shoulder': 'left',
            'beats': 16,
          },
        ),
        Figure(
          move: 'starburst',
          params: const {
            'direction': 'clockwise',
            'travel': 2,
            'who': 'role2s',
            'whom': 'partners',
          },
        ),
        Figure(
          move: 'trade_the_wave',
          params: const {
            'sides': 'neighbors',
            'center': 'role2s',
            'centerHand': 'left',
            'axis': 'along',
            'balance': true,
            'beats': 8,
          },
        ),
        // Two moves at this release; one figure with `passType` at head.
        Figure(
          move: 'pass_by',
          params: const {'who': 'partners', 'shoulder': 'left'},
        ),
        Figure(move: 'pass_by'),
        Figure(move: 'pass_through', params: const {'where': 'across'}),
        Figure(move: 'pass_through'),
        // v39: a circle may leave its distance unstated.
        Figure(
          move: 'circle',
          params: const {'direction': 'right', 'places': 'unspecified'},
        ),
        // v38: third corners and opposites.
        Figure(
          move: 'circular_hey',
          params: const {
            'who': 'thirdCorners',
            'who2': 'opposites',
            'changes': 3,
          },
        ),
        // v0.9 sequences and v0.10 container titles.
        Figure.meanwhile(
          title: 'Flutterwheel',
          figures: [
            Figure.sequence(
              title: 'Ones go',
              figures: [
                Figure(move: 'balance', params: const {'who': 'ones'}),
                Figure(move: 'swing', params: const {'who': 'ones'}),
              ],
              beats: 8,
            ),
            Figure(move: 'swing', params: const {'who': 'twos'}),
          ],
          beats: 8,
        ),
      ],
      createdAt: t0,
      updatedAt: t0,
    ),
  );
  // B: an English country dance, stored before the ECD taxonomy existed:
  // contra moves and a contra shape, which head's opt-in ECD migration must
  // not have rewritten on its own.
  await repos.dances.create(
    Dance(
      id: 'd-ecd',
      title: 'Hole in the Wall',
      form: DanceForm.ecd,
      formation: const Formation(FormationShape.dupleProper),
      progression: Progression.single,
      phraseStructure: '4*8*3',
      figures: [
        Figure(move: 'pass_through', params: const {'where': 'along'}),
        Figure(move: 'long_lines', params: const {'beats': 8}),
      ],
      callingNotes: 'Waltz time, 3/4.',
      composedOn: PartialDate(1695),
      createdAt: t0,
      updatedAt: t0,
    ),
  );
  // C: a square dance.
  await repos.dances.create(
    Dance(
      id: 'd-square',
      title: 'Grand Square Thing',
      form: DanceForm.square,
      formation: const Formation(FormationShape.other, detail: 'square set'),
      progression: Progression.none,
      figures: [
        Figure(
          move: 'forward_and_back',
          params: const {'formation': 'headCouples'},
        ),
      ],
      mixer: true,
      createdAt: t0,
      updatedAt: t0,
    ),
  );

  await repos.programs.create(
    Program(
      id: 'p-gig',
      title: 'Greenfield Gig',
      eventDate: DateTime.utc(2026, 11, 14),
      venue: 'Town Hall',
      venueId: 'v-hall',
      caller: 'Alex Caller',
      band: 'Hot Pickles',
      status: ProgramStatus.performed,
      hideAlternates: true,
      dialectName: 'Gender-free (larks/robins)',
      payMinorUnits: 25050,
      payCurrency: 'USD',
      slots: [
        ProgramSlot(
          id: 'g-1',
          position: 0,
          danceId: 'd-v10',
          performedAt: DateTime.utc(2026, 11, 14, 20),
        ),
        ProgramSlot(id: 'g-2', position: 1, danceId: 'd-ecd', isAlt: true),
      ],
      createdAt: t0,
      updatedAt: t0,
    ),
  );

  // The glossary holds figures too, outside `dances.figures_json`.
  await repos.userGlossary.upsert(
    UserGlossaryEntry(
      id: 'ug-compound',
      kindName: UserGlossaryEntryKind.compound.name,
      name: 'Pass and eight',
      definition: 'A pass by then a long figure 8.',
      description: '',
      keywords: const ['passeight'],
      payload: CompoundDefinition(
        params: const [CompoundParam(key: 'who', kind: ParamKind.dancerSet)],
        figures: [
          Figure(move: 'pass_by', params: const {'who': 'neighbors'}),
          Figure(
            move: 'figure_8',
            params: const {'fraction': 'other', 'amount': 2},
          ),
        ],
        bindings: const [
          CompoundSlotBinding(figureIndex: 0, slotKey: 'who', paramKey: 'who'),
        ],
      ).toJson(),
      createdAt: t0,
    ),
    at: t0,
  );
  await repos.figureNotes.set('pass_by', 'Watch the shoulder.', at: t0);

  await db.close();

  final raw = sqlite3.sqlite3.open(out.path);
  // The release's seeder stamps the difficulty levels with the wall clock.
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
    'programs',
    'program_slots',
    'settings',
    'venues',
    'choreographers',
    'user_glossary_entries',
    'figure_notes',
    'difficulty_levels',
  ]) {
    final n = raw.select('SELECT count(*) FROM $t').first.columnAt(0);
    stdout.writeln('$t: $n');
  }
  raw.execute('VACUUM');
  raw.close();
  stdout.writeln('size=${out.lengthSync()} bytes');
}
