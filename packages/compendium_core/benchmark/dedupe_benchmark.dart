// Import dedupe benchmark (`DedupeIndex.verdictFor` cost per incoming record).
//
// Builds an in-memory `DedupeIndex` over M synthetic `DedupeEntry` rows (titles
// and authors from the same generators `scalability_benchmark.dart` seeds, so
// the two harnesses describe the same kind of library), then times
// `verdictFor` for K incoming records: half re-matches of an existing entry
// (same title and author, one with a trailing edition marker), half novel
// records that match nothing. No database is needed. Records carry no
// external id, so every call takes the fuzzy scan over all M entries, which
// is the cost the large-library work measures.
//
// Run from the package root:
//
//     dart run benchmark/dedupe_benchmark.dart
//
// Tunable via environment variables:
//   DEDUPE_SIZES=500,2000,5000,20000   index sizes M to measure
//   DEDUPE_INCOMING=200                incoming records K per size
//
// Deterministic (fixed seed). Reports ms per incoming record; nothing is
// asserted.
import 'dart:io';
import 'dart:math';

import 'package:compendium_core/compendium_core.dart';

const int _authorCount = 60;

List<int> _sizes() {
  final raw = Platform.environment['DEDUPE_SIZES'];
  if (raw == null || raw.trim().isEmpty) return const [500, 2000, 5000, 20000];
  return raw
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .where((n) => n > 0)
      .toList();
}

final int _incoming =
    int.tryParse(Platform.environment['DEDUPE_INCOMING'] ?? '') ?? 200;

const _words = ['Reel', 'Jig', 'Waltz', 'Hey', 'Star', 'Ring', 'Chain'];

String _titleWord(Random rng) => _words[rng.nextInt(_words.length)];

void main() {
  final sizes = _sizes();
  stdout.writeln(
    'DedupeIndex.verdictFor — $_incoming incoming records per size '
    '(half re-matches, half novel)\n',
  );
  stdout.writeln(
    '${'M (index size)'.padRight(16)}${'build (ms)'.padLeft(12)}'
    '${'ms / record'.padLeft(14)}${'matched'.padLeft(12)}'
    '${'novel'.padLeft(8)}',
  );
  for (final m in sizes) {
    final rng = Random(1234);
    final entries = <DedupeEntry>[];
    for (var i = 0; i < m; i++) {
      entries.add(
        DedupeEntry(
          danceId: 'dance-$i',
          title: 'Dance ${_titleWord(rng)} $i',
          authorNames: ['Author ${i % _authorCount}'],
          // ~1 in 3 is an imported dance with provenance, as in the
          // scalability seed.
          source: i % 3 == 0 ? ProvenanceSource.contradb : null,
          externalId: i % 3 == 0 ? 'ext-$i' : null,
        ),
      );
    }
    final buildWatch = Stopwatch()..start();
    final index = DedupeIndex(entries);
    buildWatch.stop();

    final probes = <({String title, List<String> authors, bool existing})>[];
    for (var k = 0; k < _incoming; k++) {
      if (k.isEven) {
        // Re-match: an existing entry's title and author, spread across the
        // index; every other one carries an edition marker.
        final e = entries[(k * 7919) % m];
        probes.add((
          title: k % 4 == 0 ? e.title : '${e.title} (2nd ed.)',
          authors: e.authorNames,
          existing: true,
        ));
      } else {
        probes.add((
          title: 'Novel ${_titleWord(rng)} piece $k',
          authors: ['Newcomer ${k % 17}'],
          existing: false,
        ));
      }
    }

    var reimports = 0;
    var novel = 0;
    final watch = Stopwatch()..start();
    for (final probe in probes) {
      final verdict = index.verdictFor(
        source: ProvenanceSource.json,
        title: probe.title,
        authorNames: probe.authors,
      );
      if (verdict.kind == DedupeKind.isNew) {
        novel++;
      } else {
        reimports++;
      }
    }
    watch.stop();
    final perRecord = watch.elapsedMicroseconds / 1000.0 / probes.length;
    stdout.writeln(
      '${m.toString().padRight(16)}'
      '${(buildWatch.elapsedMicroseconds / 1000.0).toStringAsFixed(1).padLeft(12)}'
      '${perRecord.toStringAsFixed(2).padLeft(14)}'
      '${reimports.toString().padLeft(12)}${novel.toString().padLeft(8)}',
    );
  }
}
