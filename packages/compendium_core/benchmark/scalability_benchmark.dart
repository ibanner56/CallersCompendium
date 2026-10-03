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
//   SCALE_ONLY=load,collection,export,snapshot,snapshotparts,batch,author,
//              lastcalled,narrow,search,rebuild
//                          comma-separated scenario keys to run (default: all)
//
// `collection`, `snapshot`, `snapshotparts` and `batch` are the baselines the
// large-library work quotes (collection reload, sync snapshot, batch edits).
// An unknown key is silently skipped, so check the spelling.
import 'dart:convert';
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

  String get kinds =>
      'selects=$selects inserts=$inserts updates=$updates deletes=$deletes '
      'customs=$customs batches=$batches';

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

    // 1. Cold Collection load — mirrors CollectionData.load: the dance
    // hydration (where the N+1 lived) plus the six flat/aggregate lookups the
    // app issues on launch. Facet/map building is pure in-memory work (no
    // queries), so these seven reads capture the full launch query cost.
    if (wants('load')) {
      results.add(
        await _measure(dbPath, 'Cold Collection load (CollectionData reads)', (
          repos,
          _,
        ) async {
          final dances = await repos.dances.listAll();
          await repos.choreographers.listAll();
          await repos.tags.listReferencedByLiveDances();
          await repos.customFieldDefs.listAll();
          await repos.publishedSources.listAll();
          await repos.difficultyLevels.listAll();
          await repos.programs.programDerivedCounts();
          return dances.length;
        }),
      );
    }

    // 1b. Warm Collection reload — the same seven reads as `load`, repeated on
    // a connection that has already served them once (the app's reload after
    // every write), then `programDerivedCounts()` alone for the ratio.
    if (wants('collection')) {
      Future<int> readAll(CompendiumRepositories repos) async {
        final dances = await repos.dances.listAll();
        await repos.choreographers.listAll();
        await repos.tags.listReferencedByLiveDances();
        await repos.customFieldDefs.listAll();
        await repos.publishedSources.listAll();
        await repos.programs.programDerivedCounts();
        await repos.difficultyLevels.listAll();
        return dances.length;
      }

      results.addAll(
        await _measureSeries(
          dbPath,
          [
            (
              'Collection reload — full read set (warm)',
              (repos, _) => readAll(repos),
            ),
            (
              'Collection reload — programDerivedCounts only',
              (repos, _) async {
                final counts = await repos.programs.programDerivedCounts();
                return counts.callCounts.length;
              },
            ),
          ],
          setup: (repos) async {
            await readAll(repos);
          },
        ),
      );
    }

    // 2. Backup export — the ArchiveExporter snapshot (where the N+1 lived)
    // plus encodeArchive (`jsonEncode(archiveToJson(...))`). This is a core-only
    // proxy for the app's BackupService.exportToJson
    // (app/lib/src/data/backup_service.dart), which is not a stage of that
    // path: it calls encodeBackup, which embeds archiveToJson in the full
    // backup document, JSON-encodes that, checksums it and wraps it in the
    // container. So the figure covers the snapshot reads and the archive
    // encoding work, but not the document/checksum/container encoding or the
    // app's small settings/dialect/theme reads.
    if (wants('export')) {
      results.add(
        await _measure(dbPath, 'Backup export (snapshot + encodeArchive)', (
          repos,
          _,
        ) async {
          final archive = await ArchiveExporter(repos).export();
          final json = encodeArchive(
            archive,
            mode: ArchiveSerializationMode.backup,
          );
          if (json.isEmpty) throw StateError('empty backup payload');
          return archive.dances.length;
        }),
      );
    }

    // 2b. Sync snapshot — CompendiumSyncStorage.snapshot() with a null syncId
    // (so `_previouslyUsed` loads the stored marker but derives no verifier).
    // Cold on a fresh connection, then warm on the same connection.
    if (wants('snapshot')) {
      Future<int> snap(CompendiumRepositories repos) async {
        final snapshot = await CompendiumSyncStorage(repos).snapshot();
        return snapshot.local.length;
      }

      results.addAll(
        await _measureSeries(dbPath, [
          ('Sync snapshot (cold)', (repos, _) => snap(repos)),
          ('Sync snapshot (warm)', (repos, _) => snap(repos)),
        ]),
      );
    }

    // 2c. Per-record snapshot steps over every dance: build the blob, encode it
    // to UTF-8 canonical JSON, hash it — the three steps snapshot() repeats per
    // dance. All three are public, so they are timed separately (the dance
    // reads are excluded). Statement counts cover only the reads.
    if (wants('snapshotparts')) {
      results.add(
        await _measure(dbPath, 'Snapshot per-record steps (reads only)', (
          repos,
          _,
        ) async {
          final db = repos.db;
          final customFields = await repos.customFieldDefs.listAllWithDeleted();
          final allowed = {
            for (final entry in customFields)
              if (entry.field.shareable && !entry.deleted) entry.field.id,
          };
          final dances = await repos.dances.listAll(includeDeleted: true);
          final rows = {
            for (final row in await db.select(db.dances).get()) row.id: row,
          };
          final blobWatch = Stopwatch();
          final encodeWatch = Stopwatch();
          final hashWatch = Stopwatch();
          var built = 0;
          for (final dance in dances) {
            final row = rows[dance.id];
            if (row == null) continue;
            blobWatch.start();
            final blob = syncRecordBlobForEntity(
              SyncRecordKind.dance,
              dance,
              updatedAt: row.updatedAt,
              deletedAt: row.deletedAt,
              existenceAt: row.existenceAt ?? row.updatedAt,
              allowedCustomFieldIds: allowed,
            );
            blobWatch.stop();
            if (blob == null) continue;
            encodeWatch.start();
            final bytes = encodeSyncRecordBlobUtf8(blob);
            encodeWatch.stop();
            hashWatch.start();
            sha256Hex(bytes);
            hashWatch.stop();
            built++;
          }
          stdout.writeln(
            '    syncRecordBlobForEntity ×$built: '
            '${_ms(blobWatch)} ms | encodeSyncRecordBlobUtf8: '
            '${_ms(encodeWatch)} ms | sha256Hex: ${_ms(hashWatch)} ms',
          );
          return built;
        }),
      );
    }

    // 2d. Batch edit — setLevelForMany over 100 then 1,000 seeded ids. Two
    // levels, so every id in each run really changes (a dance already at the
    // target is skipped, which would understate the second run).
    if (wants('batch')) {
      final batchNow = DateTime.utc(2026, 1, 1);
      final levels = <String>[];
      results.addAll(
        await _measureSeries(
          dbPath,
          [
            for (final (run, n) in [
              100,
              1000,
            ].map((n) => min(n, danceCount)).indexed)
              (
                'Batch setLevelForMany ($n ids)',
                (repos, counter) async {
                  final level = levels[run];
                  final changed = await repos.dances.setLevelForMany(
                    [for (var i = 0; i < n; i++) 'dance-$i'],
                    difficultyLevelId: level,
                    now: batchNow,
                  );
                  return changed;
                },
              ),
          ],
          setup: (repos) async {
            for (var l = 0; l < 2; l++) {
              final level = await repos.difficultyLevels.createCustom(
                label: 'Bench level $l',
                position: 100 + l,
              );
              levels.add(level.id);
            }
          },
        ),
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
    '  ${label.padRight(48)}  '
    '${result.ms.toStringAsFixed(1).padLeft(9)} ms  '
    '${result.queries.toString().padLeft(8)} queries  '
    '(${result.rows} rows)',
  );
  await db.close();
  return result;
}

String _ms(Stopwatch w) => (w.elapsedMicroseconds / 1000.0).toStringAsFixed(1);

/// Runs several scenarios back to back on ONE connection, so every entry after
/// the first sees warm caches. [setup], when given, runs once untimed before
/// the first entry (warm-up reads, or fixture rows); the counter is reset before each entry.
Future<List<_Result>> _measureSeries(
  String dbPath,
  List<
    (
      String,
      Future<int> Function(
        CompendiumRepositories repos,
        _CountingInterceptor c,
      ),
    )
  >
  entries, {
  Future<void> Function(CompendiumRepositories repos)? setup,
}) async {
  final counter = _CountingInterceptor();
  final db = CompendiumDatabase(
    NativeDatabase(File(dbPath)).interceptWith(counter),
  );
  final repos = CompendiumRepositories(db, contraTaxonomy);
  await db.customSelect('SELECT 1').get();
  if (setup != null) await setup(repos);
  final out = <_Result>[];
  for (final (label, body) in entries) {
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
      '  ${label.padRight(48)}  '
      '${result.ms.toStringAsFixed(1).padLeft(9)} ms  '
      '${result.queries.toString().padLeft(8)} queries  '
      '(${result.rows} rows)  [${counter.kinds}]',
    );
    out.add(result);
  }
  await db.close();
  return out;
}

void _report(List<_Result> results) {
  stdout.writeln('\n=== Summary (N = $danceCount dances) ===');
  stdout.writeln(
    '${'Scenario'.padRight(48)}  ${'wall (ms)'.padLeft(9)}  '
    '${'queries'.padLeft(8)}',
  );
  for (final r in results) {
    stdout.writeln(
      '${r.label.padRight(48)}  ${r.ms.toStringAsFixed(1).padLeft(9)}  '
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
  // Same renderer DanceRepository._rebuildDerived uses, so the seeded
  // dance_figures / FTS text matches what a real create + rebuild produces.
  final renderer = FigureRenderer(contraTaxonomy);

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

    // Build the figures FIRST, then persist canonical `figures_json` alongside
    // the derived `dance_figures` / FTS rows so all three agree. listAll()
    // hydrates figures from figures_json and rebuildAllDerived() recomputes the
    // derived rows from it, so seeding an empty figures_json (with derived rows
    // populated out of band) would make both paths skip the figure decode /
    // render / insert work this audit is meant to measure.
    final figureCount = 8 + rng.nextInt(5); // 8..12
    final figures = <Figure>[
      for (var f = 0; f < figureCount; f++)
        Figure(
          move: _moves[rng.nextInt(_moves.length)],
          params: {'who': _whos[rng.nextInt(_whos.length)], 'beats': 16},
          progression: f == figureCount - 1,
        ),
    ];

    insDance.execute([
      id,
      title,
      forms[i % forms.length].name,
      shapes[i % shapes.length].name,
      progressions[i % progressions.length].name,
      '',
      encodeFigures(figures),
      '',
      '',
      statuses[i % statuses.length].name,
      '[]',
      now + i,
      now + i,
    ]);

    final canonicalTexts = <String>[];
    for (var f = 0; f < figures.length; f++) {
      final figure = figures[f];
      final canonicalText = renderer.renderCanonical(figure);
      canonicalTexts.add(canonicalText);
      insFigure.execute([
        id,
        f,
        figure.move,
        figure.beats,
        figure.progression ? 1 : 0,
        jsonEncode(figure.params),
        canonicalText,
        _sections[f % _sections.length],
      ]);
    }
    final figuresText = canonicalTexts.join(' ');

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
      figuresText.trim(),
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
