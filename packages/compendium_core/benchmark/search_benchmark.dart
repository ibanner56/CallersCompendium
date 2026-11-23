// Search performance benchmark (`docs/design/search.md` "Performance").
//
// Builds ~20k synthetic dances (8–12 figures each, varied moves / sections /
// authors / tags / custom fields) into an *on-disk* SQLite database, then
// times a representative query set through the real [FilterCompiler] /
// [DanceRepository.search] path. Asserts the median wall-clock per query stays
// well under the 50 ms target from storage.md.
//
// Run from the package root:
//
//     dart run benchmark/search_benchmark.dart
//
// Deterministic (fixed seed) so runs are comparable. The absolute threshold is
// generous so a slow CI runner's variance doesn't flake the build; the real
// regression signal is the reported median.
import 'dart:io';
import 'dart:math';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const int danceCount = 20000;
const int warmupIterations = 5;
const int measureIterations = 25;

/// Fail threshold (median). Generous vs. the 50 ms target to tolerate CI
/// runner variance; the reported median is the regression signal.
const double failMedianMs = 50.0;

final _moves = [
  'swing',
  'balance',
  'petronella',
  'do_si_do',
  'allemande',
  'long_lines',
  'chain',
  'promenade',
  'pass_through',
  'right_left_through',
];
final _sections = ['A1', 'A2', 'B1', 'B2'];
final _meters = ['6/8', '3/2', '2/2', '9/8', '4/4', '3/4'];
final _keys = ['D minor', 'G', 'A minor', 'D', 'E minor', 'C'];
final _whos = ['partners', 'neighbors', 'role1s', 'role2s'];
const int _authorCount = 60;
const int _tagCount = 24;

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('compendium_bench_');
  final dbPath = p.join(dir.path, 'bench.sqlite');
  try {
    stdout.writeln('Seeding $danceCount dances into $dbPath …');
    final seedWatch = Stopwatch()..start();
    final seeded = await _seed(dbPath);
    seedWatch.stop();
    stdout.writeln('Seeded in ${seedWatch.elapsedMilliseconds} ms.');

    // The app's connection setup (WAL, busy timeout and `cc_venue_key`), so
    // the benchmark times the connection the app opens.
    final db = CompendiumDatabase(
      NativeDatabase(File(dbPath), setup: applyCompendiumSqliteSetup),
    );
    final dances = DanceRepository(db, contraTaxonomy);
    final count =
        (await db.customSelect('SELECT COUNT(*) AS c FROM dances').get()).single
            .read<int>('c');
    if (count != danceCount) {
      throw StateError('expected $danceCount dances, found $count');
    }

    final queries = <String, ({DanceFilter filter, SearchSort sort})>{
      'bare FullText': (
        filter: const FullTextFilter('swing'),
        sort: SearchSort.relevance,
      ),
      'All fields, title sort': (
        filter: const FullTextFilter('swing'),
        sort: SearchSort.title,
      ),
      'All fields, accented word': (
        filter: const FullTextFilter('mineur'),
        sort: SearchSort.title,
      ),
      'Meter facet (two chips)': (
        filter: const OrFilter([MeterFilter('6/8'), MeterFilter('9/8')]),
        sort: SearchSort.title,
      ),
      'single facet (Form)': (
        filter: const FormFilter(DanceForm.contra),
        sort: SearchSort.title,
      ),
      'multi-facet And': (
        filter: const AndFilter([
          FormFilter(DanceForm.contra),
          TagFilter('tag-3'),
          StatusFilter(DanceStatus.active),
        ]),
        sort: SearchSort.title,
      ),
      'Figure leaf (move+param+section)': (
        filter: FigureFilter.leaf(
          'petronella',
          params: const {'who': 'partners'},
          section: 'B1',
        ),
        sort: SearchSort.title,
      ),
      'Then sequence': (
        filter: ThenFilter(
          FigureLeaf('petronella', section: 'A1'),
          FigureLeaf('swing'),
        ),
        sort: SearchSort.title,
      ),
    };

    var worstMedian = 0.0;
    var failed = false;
    stdout.writeln('\nQuery timings (median of $measureIterations runs):');
    for (final entry in queries.entries) {
      final median = await _time(
        () => dances.search(entry.value.filter, sort: entry.value.sort),
      );
      worstMedian = max(worstMedian, median);
      final ok = median < failMedianMs;
      failed = failed || !ok;
      stdout.writeln(
        '  ${ok ? 'ok ' : 'SLOW'}  '
        '${median.toStringAsFixed(2).padLeft(7)} ms  ${entry.key}',
      );
    }

    await db.close();

    // Suggestions (#2343): the builder's Suggested sort ranks the picker's
    // current results, which can be the whole collection, off the UI thread,
    // and ranks them again after each dance added. This times it as the app
    // does it, through a SuggestionWorker, for every seeded dance at the end of
    // a ten-dance program at a venue: building the request (the per-candidate
    // projection), sending it, ranking and returning. The longest block is
    // the longest the calling (UI) isolate went without a turn of its event
    // loop meanwhile, which is what a dropped frame would be.
    //
    // Cold: a new worker, sent every candidate. Re-rank: the same worker
    // after one more dance is added, which sends only the program and ids.
    final cold = <({double build, double total, double block})>[];
    final warm = <({double build, double total, double block})>[];
    for (var i = 0; i <= rankIterations; i++) {
      final worker = SuggestionWorker();
      try {
        final first = await _timeRank(worker, seeded, programLength: 10);
        final again = await _timeRank(worker, seeded, programLength: 11);
        if (i == 0) continue; // warm-up
        cold.add(first);
        warm.add(again);
      } finally {
        worker.dispose();
      }
    }
    final rankMedian = _median([for (final r in cold) r.total]);
    final rankOk = rankMedian < failRankMedianMs;
    failed = failed || !rankOk;
    stdout.writeln(
      '\nSuggested sort: ranking $danceCount dances '
      '(median of $rankIterations runs):',
    );
    for (final (label, runs) in [('first rank', cold), ('re-rank', warm)]) {
      stdout.writeln(
        '  $label: build ${_median([for (final r in runs) r.build]).toStringAsFixed(2)} ms, '
        'longest block ${_median([for (final r in runs) r.block]).toStringAsFixed(2)} ms, '
        'total ${_median([for (final r in runs) r.total]).toStringAsFixed(2)} ms',
      );
    }
    stdout.writeln(
      '  ${rankOk ? 'ok ' : 'SLOW'}  first rank total '
      '${rankMedian.toStringAsFixed(2).padLeft(7)} ms '
      '(threshold ${failRankMedianMs.toStringAsFixed(0)} ms)',
    );

    stdout.writeln(
      '\nWorst median: ${worstMedian.toStringAsFixed(2)} ms '
      '(threshold ${failMedianMs.toStringAsFixed(0)} ms).',
    );
    if (failed) {
      stderr.writeln(
        'BENCHMARK FAILED: a query exceeded the median threshold.',
      );
      exitCode = 1;
    } else {
      stdout.writeln('Benchmark passed.');
    }
  } finally {
    await dir.delete(recursive: true);
  }
}

/// Runs of the ranking case. Fewer than the queries: one run ranks the whole
/// collection.
const int rankIterations = 5;

/// Fail threshold for ranking the whole collection (median). The ranking runs
/// off the UI thread, behind results already shown in their plain order, so
/// this guards against a pathological regression, not a frame budget; the
/// reported median is the signal.
const double failRankMedianMs = 5000.0;

/// The request the builder would send: every seeded dance as a candidate, in
/// seed order, for the end of a program of the first ten, at a venue where
/// one dance in ten was called on a date across the last year.
SuggestionRequest _rankRequest(List<Dance> dances, {int programLength = 10}) {
  final program = dances.take(programLength).toList();
  return SuggestionRequest(
    slotsBefore: [
      for (var i = 0; i < program.length; i++)
        ProgramSlot(id: 'slot-$i', position: i, danceId: program[i].id),
    ],
    programDances: {
      for (final d in program) d.id: SuggestionCandidate.fromDance(d),
    },
    candidates: [for (final d in dances) SuggestionCandidate.fromDance(d)],
    taxonomy: shippedTaxonomies.anyForm,
    settings: SuggestionSettings.defaults,
    today: DateTime.utc(2026, 11, 23),
    levels: DifficultyLevel.shipped,
    hasVenue: true,
    calledHere: {
      for (var i = 0; i < dances.length; i += 10)
        dances[i].id: DateTime.utc(2025, 12, 1).add(Duration(days: i % 365)),
    },
  );
}

/// One rank through [worker], as the picker does it, with a probe that
/// records the longest stretch the calling isolate's event loop was blocked.
Future<({double build, double total, double block})> _timeRank(
  SuggestionWorker worker,
  List<Dance> seeded, {
  required int programLength,
}) async {
  final clock = Stopwatch()..start();
  var done = false;
  var longest = 0;
  final probe = () async {
    while (!done) {
      final before = clock.elapsedMicroseconds;
      await Future<void>.delayed(Duration.zero);
      longest = max(longest, clock.elapsedMicroseconds - before);
    }
  }();
  // Let the probe take its first turn.
  await Future<void>.delayed(Duration.zero);
  final start = clock.elapsedMicroseconds;
  final request = _rankRequest(seeded, programLength: programLength);
  final built = clock.elapsedMicroseconds - start;
  await worker.rank(request);
  final total = clock.elapsedMicroseconds - start;
  done = true;
  await probe;
  return (
    build: built / 1000.0,
    total: total / 1000.0,
    block: longest / 1000.0,
  );
}

double _median(List<double> samples) {
  final sorted = [...samples]..sort();
  return sorted[sorted.length ~/ 2];
}

Future<double> _time(Future<void> Function() run) async {
  for (var i = 0; i < warmupIterations; i++) {
    await run();
  }
  final samples = <double>[];
  for (var i = 0; i < measureIterations; i++) {
    final w = Stopwatch()..start();
    await run();
    w.stop();
    samples.add(w.elapsedMicroseconds / 1000.0);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

/// Bulk-seeds the corpus with raw prepared statements for speed (the benchmark
/// measures query time, not seed time). The schema — including the v2 `section`
/// column, indexes and the FTS5 table — is created first by opening through
/// [CompendiumDatabase].
///
/// Returns the same dances as models, figures included, for the ranking case:
/// the seeded rows store their figures in `dance_figures`, not `figures_json`.
Future<List<Dance>> _seed(String dbPath) async {
  final models = <Dance>[];
  // 1. Create the schema via the real database (onCreate), then close.
  final schemaDb = CompendiumDatabase(NativeDatabase(File(dbPath)));
  await schemaDb.customSelect('SELECT 1').get();
  await schemaDb.close();

  // 2. Bulk-insert through a raw connection with prepared statements.
  final raw = sqlite3.sqlite3.open(dbPath);
  raw.execute('PRAGMA foreign_keys = ON');
  raw.execute('PRAGMA journal_mode = WAL');
  raw.execute('BEGIN');

  final rng = Random(1234);
  const now = 1767225600; // fixed epoch seconds

  // Parents first (FK targets).
  final insAuthor = raw.prepare(
    'INSERT INTO choreographers (id, name) VALUES (?, ?)',
  );
  for (var a = 0; a < _authorCount; a++) {
    insAuthor.execute(['author-$a', 'Author $a']);
  }
  insAuthor.close();

  final insTag = raw.prepare('INSERT INTO tags (id, name) VALUES (?, ?)');
  for (var t = 0; t < _tagCount; t++) {
    insTag.execute(['tag-$t', 'tag$t']);
  }
  insTag.close();

  raw.execute(
    "INSERT INTO custom_field_defs (id, key, label, type, show_in_list, "
    "searchable) VALUES ('cf-diff', 'difficulty', 'Difficulty', 'number', 0, 1)",
  );
  raw.execute(
    "INSERT INTO custom_field_defs (id, key, label, type, show_in_list, "
    "searchable) VALUES ('cf-origin', 'origin', 'Origin', 'text', 0, 1)",
  );

  final insDance = raw.prepare(
    'INSERT INTO dances (id, title, form, formation_shape, progression, '
    'phrase_structure, figures_json, hook, calling_notes, status, tunes_json, '
    'meter, musical_key, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  );
  final insFigure = raw.prepare(
    'INSERT INTO dance_figures (dance_id, idx, move, beats, progression, '
    'params_json, canonical_text, section) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  );
  final insAuthorLink = raw.prepare(
    'INSERT INTO dance_authors (dance_id, choreographer_id, position) '
    'VALUES (?, ?, ?)',
  );
  final insTagLink = raw.prepare(
    'INSERT INTO dance_tags (dance_id, tag_id) VALUES (?, ?)',
  );
  final insCfv = raw.prepare(
    'INSERT INTO custom_field_values (dance_id, field_id, value_text, '
    'value_num) VALUES (?, ?, ?, ?)',
  );
  final insFts = raw.prepare(
    'INSERT INTO dance_fts (dance_id, title, authors, hook, notes, '
    'figures_text, custom_values) VALUES (?, ?, ?, ?, ?, ?, ?)',
  );

  final forms = DanceForm.values;
  final shapes = FormationShape.values;
  final progressions = Progression.values;
  final statuses = DanceStatus.values;

  for (var i = 0; i < danceCount; i++) {
    final id = 'dance-$i';
    final title = 'Dance ${_titleWord(rng)} $i';
    insDance.execute([
      id,
      title,
      forms[i % forms.length].name,
      shapes[i % shapes.length].name,
      progressions[i % progressions.length].name,
      '', // standard 4x16 phrase structure
      '[]',
      '',
      '',
      statuses[i % statuses.length].name,
      '[]',
      // Every dance has a meter and a key, as in an English collection, so
      // the meter, key and interpreter matches are timed on every row; one in
      // twenty has a key outside ASCII, which takes the Dart fold.
      _meters[i % _meters.length],
      i % 20 == 0 ? 'Ré mineur' : _keys[i % _keys.length],
      now + i,
      now + i,
    ]);

    final figureCount = 8 + rng.nextInt(5); // 8..12
    final figuresText = StringBuffer();
    final figures = <Figure>[];
    var beat = 0;
    for (var f = 0; f < figureCount; f++) {
      final move = _moves[rng.nextInt(_moves.length)];
      final who = _whos[rng.nextInt(_whos.length)];
      final section = _sections[(beat ~/ 16) % _sections.length];
      final params = '{"who":"$who","beats":16}';
      figuresText.write('$who $move ');
      insFigure.execute([id, f, move, 16, 0, params, '$who $move', section]);
      figures.add(Figure(move: move, params: {'who': who, 'beats': 16}));
      beat += 16;
    }
    models.add(
      Dance(
        id: id,
        title: title,
        form: forms[i % forms.length],
        formation: Formation(shapes[i % shapes.length]),
        figures: figures,
        difficultyLevelId:
            DifficultyLevel.shipped[i % DifficultyLevel.shipped.length].id,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

    insAuthorLink.execute([id, 'author-${i % _authorCount}', 0]);

    final tagN = i % 3; // 0..2 tags
    for (var t = 0; t < tagN; t++) {
      insTagLink.execute([id, 'tag-${(i + t) % _tagCount}']);
    }

    insCfv.execute([id, 'cf-diff', null, (1 + i % 5).toDouble()]);
    insCfv.execute([id, 'cf-origin', 'origin ${i % 7}', null]);

    insFts.execute([
      id,
      title,
      'Author ${i % _authorCount}',
      '',
      '',
      figuresText.toString().trim(),
      'origin ${i % 7} ${1 + i % 5}',
    ]);
  }

  insDance.close();
  insFigure.close();
  insAuthorLink.close();
  insTagLink.close();
  insCfv.close();
  insFts.close();

  raw.execute('COMMIT');
  raw.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  raw.close();
  return models;
}

String _titleWord(Random rng) {
  const words = ['Reel', 'Jig', 'Waltz', 'Hey', 'Star', 'Ring', 'Chain'];
  return words[rng.nextInt(words.length)];
}
