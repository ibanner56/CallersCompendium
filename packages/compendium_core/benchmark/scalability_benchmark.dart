// Scalability audit harness (issue: "smooth at ~20k dances" validation).
//
// The published `search_benchmark.dart` only exercises `DanceRepository.search`,
// which returns *ids* through pure SQL and never touches the per-dance
// `_toModel` hydration. This harness measures the paths that DO hydrate every
// dance — cold Collection load, backup export, post-migration rebuild — plus the
// whole-collection author / last-called sorts and a text search, capturing BOTH
// wall-clock time AND the exact SQL statement count (via a drift
// `QueryInterceptor`).
//
// Run from the package root:
//
//     dart run benchmark/scalability_benchmark.dart
//
// Deterministic (fixed seed). Each scenario runs on a freshly opened connection
// so the statement count reflects a cold first access (as on app launch).
//
// Tunable via environment variables (used to characterize scaling without
// re-running the full 20k corpus each time):
//   SCALE_DANCES=20000    number of dances to seed
//   SCALE_PROGRAMS=500     number of programs to seed
//   SCALE_ONLY=load,export,author,lastcalled,narrow,search,rebuild
//                          comma-separated scenario keys to run (default: all)
import 'dart:io';
import 'dart:math';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

final int danceCount =
    int.tryParse(Platform.environment['SCALE_DANCES'] ?? '') ?? 20000;
final int programCount =
    int.tryParse(Platform.environment['SCALE_PROGRAMS'] ?? '') ?? 500;
const int slotsPerProgram = 16;

Set<String>? _only() {
  final raw = Platform.environment['SCALE_ONLY'];
  if (raw == null || raw.trim().isEmpty) return null;
  return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
}

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
const int _sourceCount = 40;

/// Counts every SQL statement drift sends to the executor, split by kind. Used
/// to prove the O(1 + 6N) query fan-out empirically rather than by inspection.
class _CountingInterceptor extends QueryInterceptor {
  int selects = 0;
  int inserts = 0;
  int updates = 0;
  int deletes = 0;
  int customs = 0;
  int batches = 0;

  int get total => selects + inserts + updates + deletes + customs + batches;

  void reset() {
    selects = inserts = updates = deletes = customs = batches = 0;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    inserts++;
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    updates++;
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    deletes++;
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    customs++;
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    batches++;
    return super.runBatched(executor, statements);
  }
}

class _Result {
  _Result(this.label, this.ms, this.queries, this.rows);
  final String label;
  final double ms;
  final int queries;
  final int rows;
}

Future<void> main() async {
  final only = _only();
  bool wants(String key) => only == null || only.contains(key);

  final dir = await Directory.systemTemp.createTemp('compendium_scale_');
  final dbPath = p.join(dir.path, 'scale.sqlite');
  final results = <_Result>[];
  try {
    stdout.writeln('Seeding $danceCount dances + $programCount programs …');
    final seedWatch = Stopwatch()..start();
    await _seed(dbPath);
    seedWatch.stop();
    stdout.writeln('Seeded in ${seedWatch.elapsedMilliseconds} ms.\n');

    // 1. Cold Collection load — hydrates every dance via listAll/_toModel.
    if (wants('load')) {
      results.add(
        await _measure(dbPath, 'Cold Collection load (listAll)', (
          repos,
          _,
        ) async {
          final dances = await repos.dances.listAll();
          return dances.length;
        }),
      );
    }

    // 2. Backup export — listAll(includeDeleted) for dances + programs + lookups.
    if (wants('export')) {
      results.add(
        await _measure(dbPath, 'Backup export (ArchiveExporter)', (
          repos,
          _,
        ) async {
          final archive = await ArchiveExporter(repos).export();
          return archive.dances.length;
        }),
      );
    }

    // 3. Whole-collection author sort (match-all filter).
    if (wants('author')) {
      results.add(
        await _measure(dbPath, 'Author sort — whole collection', (
          repos,
          _,
        ) async {
          final ids = await repos.dances.search(
            const AndFilter([]),
            sort: SearchSort.author,
          );
          return ids.length;
        }),
      );
    }

    // 4. Whole-collection last-called sort (match-all filter).
    if (wants('lastcalled')) {
      results.add(
        await _measure(dbPath, 'Last-called sort — whole collection', (
          repos,
          _,
        ) async {
          final ids = await repos.dances.search(
            const AndFilter([]),
            sort: SearchSort.lastCalled,
          );
          return ids.length;
        }),
      );
    }

    // 4b. Narrow-result author sort — shows the sort helper scans the entire
    // collection regardless of how few rows the filter actually returns.
    if (wants('narrow')) {
      results.add(
        await _measure(dbPath, 'Author sort — narrow result (1 author)', (
          repos,
          _,
        ) async {
          final ids = await repos.dances.search(
            const AuthorFilter('author-0'),
            sort: SearchSort.author,
          );
          return ids.length;
        }),
      );
    }

    // 5. Text search (FTS) — the path the published benchmark exercises.
    if (wants('search')) {
      results.add(
        await _measure(dbPath, 'Text search (searchText "swing")', (
          repos,
          _,
        ) async {
          final ids = await repos.dances.searchText('swing');
          return ids.length;
        }),
      );
    }

    // 6. Post-migration rebuild — listAll(includeDeleted) + per-dance rebuild,
    // all in one transaction. Mutates derived tables to equivalent content, so
    // run last.
    if (wants('rebuild')) {
      results.add(
        await _measure(dbPath, 'Post-migration rebuildAllDerived', (
          repos,
          _,
        ) async {
          await repos.dances.rebuildAllDerived();
          return danceCount;
        }),
      );
    }

    _report(results);
  } finally {
    await dir.delete(recursive: true);
  }
}

/// Opens a fresh instrumented connection, runs [body] once, and records the
/// wall-clock time and SQL statement count for just that operation (the open /
/// warm-up `SELECT 1` is excluded by resetting the counter first).
Future<_Result> _measure(
  String dbPath,
  String label,
  Future<int> Function(CompendiumRepositories repos, _CountingInterceptor c)
  body,
) async {
  final counter = _CountingInterceptor();
  final db = CompendiumDatabase(
    NativeDatabase(File(dbPath)).interceptWith(counter),
  );
  final repos = CompendiumRepositories(db, contraTaxonomy);
  await db.customSelect('SELECT 1').get(); // force open, warm nothing else
  counter.reset();
  final watch = Stopwatch()..start();
  final rows = await body(repos, counter);
  watch.stop();
  final result = _Result(
    label,
    watch.elapsedMicroseconds / 1000.0,
    counter.total,
    rows,
  );
  stdout.writeln(
    '  ${label.padRight(40)}  '
    '${result.ms.toStringAsFixed(1).padLeft(9)} ms  '
    '${result.queries.toString().padLeft(8)} queries  '
    '(${result.rows} rows)',
  );
  await db.close();
  return result;
}

void _report(List<_Result> results) {
  stdout.writeln('\n=== Summary (N = $danceCount dances) ===');
  stdout.writeln(
    '${'Scenario'.padRight(40)}  ${'wall (ms)'.padLeft(9)}  '
    '${'queries'.padLeft(8)}',
  );
  for (final r in results) {
    stdout.writeln(
      '${r.label.padRight(40)}  ${r.ms.toStringAsFixed(1).padLeft(9)}  '
      '${r.queries.toString().padLeft(8)}',
    );
  }
}

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

  final insSource = raw.prepare(
    'INSERT INTO published_sources (id, title, author, year) VALUES (?, ?, ?, ?)',
  );
  for (var s = 0; s < _sourceCount; s++) {
    insSource.execute(['source-$s', 'Collection $s', 'Editor $s', 1990 + s]);
  }
  insSource.close();

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
  final insSourceLink = raw.prepare(
    'INSERT INTO dance_sources (dance_id, source_id, page, number, position) '
    'VALUES (?, ?, ?, ?, ?)',
  );
  final insLink = raw.prepare(
    'INSERT INTO dance_links (id, dance_id, kind, url, label) '
    'VALUES (?, ?, ?, ?, ?)',
  );
  final insProv = raw.prepare(
    'INSERT INTO provenance (dance_id, source, external_id, imported_at) '
    'VALUES (?, ?, ?, ?)',
  );
  final insFts = raw.prepare(
    'INSERT INTO dance_fts (dance_id, title, authors, hook, notes, '
    'figures_text, custom_values, sources) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
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
      '',
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

    // ~half the dances carry a published-source citation.
    if (i % 2 == 0) {
      insSourceLink.execute([
        id,
        'source-${i % _sourceCount}',
        '${i % 300}',
        null,
        0,
      ]);
    }
    // ~1 in 10 carries a video link.
    if (i % 10 == 0) {
      insLink.execute([
        'link-$i',
        id,
        'video',
        'https://example.test/$i',
        'Video',
      ]);
    }
    // ~1 in 3 is an imported dance with provenance.
    if (i % 3 == 0) {
      insProv.execute([id, 'contradb', 'ext-$i', now + i]);
    }

    insFts.execute([
      id,
      title,
      'Author ${i % _authorCount}',
      '',
      '',
      figuresText.toString().trim(),
      'origin ${i % 7} ${1 + i % 5}',
      i % 2 == 0 ? 'Collection ${i % _sourceCount}' : '',
    ]);
  }

  insDance.close();
  insFigure.close();
  insAuthorLink.close();
  insTagLink.close();
  insCfv.close();
  insSourceLink.close();
  insLink.close();
  insProv.close();
  insFts.close();

  // Programs + slots referencing dances, with performed_at, so the last-called
  // sort has real aggregate data to scan.
  final insProgram = raw.prepare(
    'INSERT INTO programs (id, title, status, notes, hide_alternates, '
    'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
  );
  final insSlot = raw.prepare(
    'INSERT INTO program_slots (id, program_id, position, dance_id, is_alt, '
    'performed_at) VALUES (?, ?, ?, ?, ?, ?)',
  );
  for (var pIdx = 0; pIdx < programCount; pIdx++) {
    final pid = 'program-$pIdx';
    insProgram.execute([
      pid,
      'Program $pIdx',
      ProgramStatus.performed.name,
      '',
      0,
      now + pIdx * 86400,
      now + pIdx * 86400,
    ]);
    for (var s = 0; s < slotsPerProgram; s++) {
      final danceIdx = rng.nextInt(danceCount);
      insSlot.execute([
        'slot-$pIdx-$s',
        pid,
        s,
        'dance-$danceIdx',
        0,
        now + pIdx * 86400 + s * 300,
      ]);
    }
  }
  insProgram.close();
  insSlot.close();

  raw.execute('COMMIT');
  raw.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  raw.close();
}

String _titleWord(Random rng) {
  const words = ['Reel', 'Jig', 'Waltz', 'Hey', 'Star', 'Ring', 'Chain'];
  return words[rng.nextInt(words.length)];
}
