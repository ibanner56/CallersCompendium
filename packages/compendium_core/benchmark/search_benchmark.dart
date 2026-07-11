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
final _whos = ['partners', 'neighbors', 'role1s', 'role2s'];
const int _authorCount = 60;
const int _tagCount = 24;

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('compendium_bench_');
  final dbPath = p.join(dir.path, 'bench.sqlite');
  try {
    stdout.writeln('Seeding $danceCount dances into $dbPath …');
    final seedWatch = Stopwatch()..start();
    await _seed(dbPath);
    seedWatch.stop();
    stdout.writeln('Seeded in ${seedWatch.elapsedMilliseconds} ms.');

    final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
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
Future<void> _seed(String dbPath) async {
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
    'created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
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
      now + i,
      now + i,
    ]);

    final figureCount = 8 + rng.nextInt(5); // 8..12
    final figuresText = StringBuffer();
    var beat = 0;
    for (var f = 0; f < figureCount; f++) {
      final move = _moves[rng.nextInt(_moves.length)];
      final who = _whos[rng.nextInt(_whos.length)];
      final section = _sections[(beat ~/ 16) % _sections.length];
      final params = '{"who":"$who","beats":16}';
      figuresText.write('$who $move ');
      insFigure.execute([id, f, move, 16, 0, params, '$who $move', section]);
      beat += 16;
    }

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
}

String _titleWord(Random rng) {
  const words = ['Reel', 'Jig', 'Waltz', 'Hey', 'Star', 'Ring', 'Chain'];
  return words[rng.nextInt(words.length)];
}
