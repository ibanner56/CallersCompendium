// Measures how often the #1907 "possible match" tier
// (`DedupeIndex.possibleTitleMatches`) would put a choice in front of a user,
// and prints a sample of the pairs it finds so they can be hand-classified as
// the same dance (or a variant of it) versus a different dance. Not shipped.
// Run from `packages/compendium_core/`:
//
//     dart run tool/measure_possible_matches.dart \
//         --tcb-dir <dir> --contradb <file.json> --sample 50 --seed 1907
//
// Either input may be omitted. `--tcb-dir` is read recursively; every `.json`
// file in it may hold one Caller's Box dance object (the `dance.php?...&
// format=JSON` shape: `ID`, `Name`, `Authors`) or a list of them. `--contradb`
// is a JSON list of ContraDB search rows (`id`, `title`, `choreographer_name`),
// as `POST https://contradb.com/api/v1/dances` returns them in its `dances`
// array, paged with `count`/`offset`; the whole catalogue is ~122 pages of 20.
//
// Authors are tokenized with `splitAuthorNames`, as both adapters do (their
// extra text sanitizing cannot change either title key, which keep only
// `[a-z0-9]`), and every decision is the real index's: nothing here
// re-implements the tier. A Caller's Box entry without an `ID` is skipped.
//
// Reported per dataset (a "self-join": each record against the rest of its own
// collection, as if importing it into a library that already holds the rest):
// - records with at least one possible match;
// - unordered pairs, and how many of them the fuzzy tier (0.72) already
//   surfaces, i.e. how many prompts are new;
// and, when both inputs are given, ContraDB records imported into a Caller's
// Box collection. A record never matches itself.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:compendium_core/compendium_core.dart';

class _Record {
  _Record(this.id, this.title, this.authors);

  final String id;
  final String title;
  final List<String> authors;

  @override
  String toString() => '$title  [${authors.join('; ')}]  ($id)';
}

void main(List<String> arguments) {
  String? option(String name) {
    final index = arguments.indexOf('--$name');
    if (index < 0) return null;
    if (index + 1 >= arguments.length) {
      throw ArgumentError('--$name needs a value');
    }
    return arguments[index + 1];
  }

  final tcbDir = option('tcb-dir');
  final contraDbFile = option('contradb');
  final sampleSize = int.parse(option('sample') ?? '50');
  final seed = int.parse(option('seed') ?? '1907');
  if (tcbDir == null && contraDbFile == null) {
    stderr.writeln('Give --tcb-dir and/or --contradb.');
    exitCode = 64;
    return;
  }

  final tcb = tcbDir == null ? null : _readTcb(Directory(tcbDir));
  final contraDb = contraDbFile == null
      ? null
      : _readContraDb(File(contraDbFile));

  if (tcb != null) _selfJoin("Caller's Box", tcb, sampleSize, seed);
  if (contraDb != null) _selfJoin('ContraDB', contraDb, sampleSize, seed);
  if (tcb != null && contraDb != null) {
    _cross(
      'ContraDB into a Caller\'s Box collection',
      contraDb,
      tcb,
      sampleSize,
      seed,
    );
  }
}

List<_Record> _readTcb(Directory dir) {
  final out = <_Record>[];
  var unreadable = 0;
  var skipped = 0;
  final files =
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on Object {
      unreadable++;
      continue;
    }
    final items = decoded is List ? decoded : [decoded];
    for (final item in items) {
      if (item is! Map || item['Name'] is! String || item['ID'] == null) {
        skipped++;
        continue;
      }
      final authors = item['Authors'];
      out.add(
        _Record(
          'tcb:${item['ID']}',
          item['Name'] as String,
          splitAuthorNames([
            if (authors is List)
              for (final a in authors)
                if (a is String) a,
          ]),
        ),
      );
    }
  }
  stdout.writeln(
    "Caller's Box: ${files.length} .json files, ${out.length} dances read, "
    '$unreadable files not valid JSON, $skipped entries without a Name or ID.',
  );
  return out;
}

List<_Record> _readContraDb(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  final rows = decoded is Map ? decoded['dances'] : decoded;
  final out = <_Record>[
    for (final row in rows as List)
      if (row is Map && row['title'] is String)
        _Record(
          'contradb:${row['id']}',
          row['title'] as String,
          splitAuthorNames([row['choreographer_name'] as String?]),
        ),
  ];
  stdout.writeln('ContraDB: ${out.length} dances read.');
  return out;
}

DedupeIndex _indexOf(List<_Record> records) => DedupeIndex([
  for (final r in records)
    DedupeEntry(danceId: r.id, title: r.title, authorNames: r.authors),
]);

void _selfJoin(String label, List<_Record> records, int sampleSize, int seed) {
  final index = _indexOf(records);
  final byId = {for (final r in records) r.id: r};
  final withAuthors = records.where((r) => r.authors.isNotEmpty).length;
  final pairs = <(String, String)>{};
  final perRecord = <int, int>{};
  var recordsWithMatch = 0;
  for (final r in records) {
    // Never the record itself: the tier excludes an equal normalizeTitle.
    final matches = index.possibleTitleMatches(r.title, r.authors);
    if (matches.isEmpty) continue;
    recordsWithMatch++;
    perRecord.update(min(matches.length, 4), (n) => n + 1, ifAbsent: () => 1);
    for (final id in matches) {
      pairs.add(r.id.compareTo(id) < 0 ? (r.id, id) : (id, r.id));
    }
  }
  // Fuzzy-scored only for records in a pair, once each (a whole-collection
  // scan per record); scoring is symmetric, so either end of a pair will do.
  final fuzzyOf = <String, Set<String>>{};
  var alreadyFuzzy = 0;
  for (final (a, b) in pairs) {
    final ra = byId[a]!;
    final fuzzy = fuzzyOf.putIfAbsent(
      a,
      () => {
        for (final c in index.fuzzyMatches(ra.title, ra.authors)) c.danceId,
      },
    );
    if (fuzzy.contains(b)) alreadyFuzzy++;
  }

  stdout
    ..writeln()
    ..writeln('== $label: self-join')
    ..writeln('records: ${records.length} ($withAuthors with authors)')
    ..writeln(
      'records with >=1 possible match: $recordsWithMatch '
      '(${_pct(recordsWithMatch, records.length)} of all records)',
    )
    ..writeln(
      '  by count of matches: '
      '${[
        for (final k in [1, 2, 3, 4]) '${k == 4 ? '4+' : k}: ${perRecord[k] ?? 0}',
      ].join(', ')}',
    )
    ..writeln(
      'unordered pairs: ${pairs.length}; already surfaced by the 0.72 fuzzy '
      'tier: $alreadyFuzzy; new to the user: ${pairs.length - alreadyFuzzy}',
    );
  _printSample(
    pairs.map((p) => (byId[p.$1]!, byId[p.$2]!)).toList(),
    sampleSize,
    seed,
  );
}

void _cross(
  String label,
  List<_Record> incoming,
  List<_Record> collection,
  int sampleSize,
  int seed,
) {
  final index = _indexOf(collection);
  final byId = {for (final r in collection) r.id: r};
  final pairs = <(_Record, _Record)>[];
  var recordsWithMatch = 0;
  var alreadyFuzzy = 0;
  for (final r in incoming) {
    final matches = index.possibleTitleMatches(r.title, r.authors);
    if (matches.isEmpty) continue;
    recordsWithMatch++;
    final fuzzy = {
      for (final c in index.fuzzyMatches(r.title, r.authors)) c.danceId,
    };
    for (final id in matches) {
      pairs.add((r, byId[id]!));
      if (fuzzy.contains(id)) alreadyFuzzy++;
    }
  }
  stdout
    ..writeln()
    ..writeln('== $label')
    ..writeln(
      'incoming records with >=1 possible match: $recordsWithMatch of '
      '${incoming.length} (${_pct(recordsWithMatch, incoming.length)})',
    )
    ..writeln(
      'pairs: ${pairs.length}; already surfaced by the 0.72 fuzzy tier: '
      '$alreadyFuzzy; new to the user: ${pairs.length - alreadyFuzzy}',
    );
  _printSample(pairs, sampleSize, seed);
}

void _printSample(List<(_Record, _Record)> pairs, int sampleSize, int seed) {
  final shuffled = [...pairs]..shuffle(Random(seed));
  final sample = shuffled.take(sampleSize).toList();
  stdout.writeln(
    'sample of ${sample.length} pairs (seed $seed), to classify by hand:',
  );
  for (var i = 0; i < sample.length; i++) {
    final (a, b) = sample[i];
    stdout
      ..writeln('  ${i + 1}. $a')
      ..writeln('     $b');
  }
}

String _pct(int n, int of) =>
    of == 0 ? 'n/a' : '${(100 * n / of).toStringAsFixed(2)}%';
