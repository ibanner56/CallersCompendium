// Import dedupe benchmark (`DedupeIndex.verdictFor` cost per incoming record).
//
// Builds an in-memory `DedupeIndex` over M synthetic `DedupeEntry` rows (titles
// and authors from the same generators `scalability_benchmark.dart` seeds, so
// the two harnesses describe the same kind of library), then times
// `verdictFor` for K incoming records: half re-matches of an existing entry
// (same title and author, every other one upper-cased), half novel records
// that match nothing. The run fails if a re-match probe comes back new or a
// novel probe comes back matched, so the advertised mix is guaranteed.
//
// Each size gets one untimed warm-up pass, then $_samples timed passes; the
// reported figure is the median pass (as `search_benchmark.dart` does), so
// first-use JIT cost does not land on whichever size runs first. No database is needed. Records carry no
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
//   DEDUPE_SAMPLES=5                   timed passes per size (median reported)
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

final int _samples =
    int.tryParse(Platform.environment['DEDUPE_SAMPLES'] ?? '') ?? 5;

const _words = ['Reel', 'Jig', 'Waltz', 'Hey', 'Star', 'Ring', 'Chain'];

String _titleWord(Random rng) => _words[rng.nextInt(_words.length)];

void main() {
  final sizes = _sizes();
  stdout.writeln(
    'DedupeIndex.verdictFor — $_incoming incoming records per size '
    '(half re-matches, half novel; median of $_samples passes)\n',
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
        // index; every other one upper-cased (normalizeTitle folds case).
        final e = entries[(k * 7919) % m];
        probes.add((
          title: k % 4 == 0 ? e.title : e.title.toUpperCase(),
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

    // One pass over every probe; also checks the advertised mix.
    ({int matched, int novel}) runPass() {
      var matched = 0;
      var novel = 0;
      for (final probe in probes) {
        final verdict = index.verdictFor(
          source: ProvenanceSource.json,
          title: probe.title,
          authorNames: probe.authors,
        );
        final isNew = verdict.kind == DedupeKind.isNew;
        if (isNew == probe.existing) {
          throw StateError(
            'probe "${probe.title}" (existing: ${probe.existing}) got '
            '${verdict.kind}',
          );
        }
        if (isNew) {
          novel++;
        } else {
          matched++;
        }
      }
      return (matched: matched, novel: novel);
    }

    runPass(); // untimed warm-up
    final passMs = <double>[];
    var counts = (matched: 0, novel: 0);
    for (var s = 0; s < max(1, _samples); s++) {
      final watch = Stopwatch()..start();
      counts = runPass();
      watch.stop();
      passMs.add(watch.elapsedMicroseconds / 1000.0);
    }
    passMs.sort();
    final medianMs = passMs[passMs.length ~/ 2];
    final reimports = counts.matched;
    final novel = counts.novel;
    final perRecord = medianMs / probes.length;
    stdout.writeln(
      '${m.toString().padRight(16)}'
      '${(buildWatch.elapsedMicroseconds / 1000.0).toStringAsFixed(1).padLeft(12)}'
      '${perRecord.toStringAsFixed(2).padLeft(14)}'
      '${reimports.toString().padLeft(12)}${novel.toString().padLeft(8)}',
    );
  }
}
