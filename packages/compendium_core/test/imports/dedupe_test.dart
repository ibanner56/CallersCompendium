import 'dart:math';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'import and sync choreography fingerprints share one field contract',
    () {
      final dance = Dance(
        id: 'fingerprint-dance',
        title: 'Fingerprint dance',
        createdAt: DateTime.utc(2026, 7, 15, 12),
        updatedAt: DateTime.utc(2026, 7, 15, 12),
      );
      final body = syncBodyForEntity(SyncRecordKind.dance, dance);

      expect(
        choreographyFingerprintForDance(dance),
        choreographyFingerprint(body),
      );
    },
  );

  test(
    'the dance fingerprint ignores collections and cannot throw on them',
    () {
      final stamp = DateTime.utc(2026, 7, 15, 12);
      final plain = Dance(
        id: 'collection-dance',
        title: 'Collection dance',
        createdAt: stamp,
        updatedAt: stamp,
      );
      // None of these is a choreography field, and the archive encoder throws
      // on a non-finite custom-field number. `ImportPipeline` calls the
      // fingerprint from a candidate loop that treats it as a predicate, so a
      // throw here would abort auto-resolution rather than decline a match.
      final decorated = plain.copyWith(
        customFields: [CustomFieldValue(fieldId: 'field', value: double.nan)],
        links: [
          DanceLink(id: 'link', kind: LinkKind.video, url: 'https://x.test'),
        ],
        sourceCitations: [SourceCitation(sourceId: 'source')],
        provenance: Provenance(
          source: ProvenanceSource.manual,
          importedAt: stamp,
        ),
      );

      expect(
        choreographyFingerprintForDance(decorated),
        choreographyFingerprintForDance(plain),
      );
    },
  );

  final choreographyCases = <({String name, Dance Function(Dance) mutate})>[
    (name: 'form', mutate: (dance) => dance.copyWith(form: DanceForm.ecd)),
    (
      name: 'formation',
      mutate: (dance) =>
          dance.copyWith(formation: const Formation(FormationShape.becketCw)),
    ),
    (
      name: 'progression',
      mutate: (dance) => dance.copyWith(progression: Progression.double),
    ),
    (
      name: 'phrase structure',
      mutate: (dance) => dance.copyWith(phraseStructure: '2*8*2'),
    ),
    (
      name: 'figures',
      mutate: (dance) => dance.copyWith(figures: [testFigure(move: 'balance')]),
    ),
    (name: 'hook', mutate: (dance) => dance.copyWith(hook: 'A different hook')),
    (
      name: 'calling notes',
      mutate: (dance) => dance.copyWith(callingNotes: 'Different notes'),
    ),
    (
      name: 'difficulty level',
      mutate: (dance) =>
          dance.copyWith(difficultyLevelId: 'difficulty-advanced'),
    ),
    (name: 'mixed level', mutate: (dance) => dance.copyWith(mixedLevel: true)),
    (name: 'mixer', mutate: (dance) => dance.copyWith(mixer: true)),
    (name: 'tunes', mutate: (dance) => dance.copyWith(tunes: const ['Jig'])),
  ];

  for (final choreographyCase in choreographyCases) {
    test('fresh attach treats ${choreographyCase.name} as significant', () {
      final stamp = DateTime.utc(2026, 7, 15, 12);
      Dance baseDance(String id, String title) =>
          Dance(id: id, title: title, createdAt: stamp, updatedAt: stamp);
      final left = baseDance('a-left', 'Shared dance');
      final right = choreographyCase.mutate(
        baseDance('b-right', 'The Shared Dance'),
      );
      SyncRecordBlob blobFor(Dance dance) => SyncRecordBlob(
        kind: SyncRecordKind.dance,
        id: dance.id,
        updatedAt: stamp,
        deletedAt: null,
        existenceAt: stamp,
        body: syncBodyForEntity(SyncRecordKind.dance, dance),
      );

      final plan = planFreshAttachDedupe([
        SyncMergeCandidate.fromBlob(blobFor(left)),
        SyncMergeCandidate.fromBlob(blobFor(right)),
      ]);

      expect(plan.merges, isEmpty);
      expect(plan.ambiguities, hasLength(1));
    });
  }

  group('normalization', () {
    test('title folds case, punctuation, diacritics, articles', () {
      expect(normalizeTitle('The Nice Combination!'), 'nice combination');
      expect(normalizeTitle('Café Béguine'), 'cafe beguine');
      expect(normalizeTitle('  A  Fine   Romance  '), 'fine romance');
    });

    test('title and author normalization compose decomposed accents', () {
      expect(normalizeTitle('Re\u0301sume\u0301'), 'resume');
      expect(normalizeTitle('Résumé'), 'resume');
      expect(normalizeAuthor('Chlo\u0308e'), 'chloe');
      expect(normalizeAuthor('Chlöe'), 'chloe');
    });

    test('author folds case and punctuation', () {
      expect(normalizeAuthor('Cary Ravitz'), 'cary ravitz');
      expect(normalizeAuthor('Gene  Hubert.'), 'gene hubert');
    });
  });

  group('DedupeIndex exact (source, externalId)', () {
    final index = DedupeIndex([
      DedupeEntry(
        danceId: 'd1',
        title: 'Rory OMore',
        source: ProvenanceSource.callersbox,
        externalId: '100',
      ),
      DedupeEntry(
        danceId: 'd2',
        title: 'Other Dance',
        source: ProvenanceSource.contradb,
        externalId: '100',
      ),
    ]);

    test('matches on both source and externalId', () {
      expect(index.findByExternalId(ProvenanceSource.callersbox, '100'), 'd1');
      expect(index.findByExternalId(ProvenanceSource.contradb, '100'), 'd2');
    });

    test('no match for wrong source or missing id', () {
      expect(index.findByExternalId(ProvenanceSource.json, '100'), isNull);
      expect(
        index.findByExternalId(ProvenanceSource.callersbox, '999'),
        isNull,
      );
      expect(index.findByExternalId(ProvenanceSource.callersbox, null), isNull);
    });

    test('verdictFor returns reimport on exact key', () {
      final v = index.verdictFor(
        source: ProvenanceSource.callersbox,
        externalId: '100',
        title: 'totally different title',
      );
      expect(v.isReimport, isTrue);
      expect(v.targetDanceId, 'd1');
    });

    test('verdictFor falls back to prior keys, in order, only when the '
        'current key has no match', () {
      final legacy = DedupeIndex([
        DedupeEntry(
          danceId: 'legacy',
          title: 'Received Before',
          source: ProvenanceSource.json,
          externalId: '457',
        ),
        DedupeEntry(
          danceId: 'current',
          title: 'Received After',
          source: ProvenanceSource.json,
          externalId: 'contradb:457',
        ),
      ]);
      // The current key wins when present.
      expect(
        legacy
            .verdictFor(
              source: ProvenanceSource.json,
              externalId: 'contradb:457',
              priorExternalIds: const ['457'],
              title: 'x',
            )
            .targetDanceId,
        'current',
      );
      // Otherwise the prior key is tried.
      expect(
        legacy
            .verdictFor(
              source: ProvenanceSource.json,
              externalId: 'callersbox:457',
              priorExternalIds: const ['457'],
              title: 'x',
            )
            .targetDanceId,
        'legacy',
      );
      // No prior key, no match: falls through to fuzzy, which finds nothing.
      expect(
        legacy
            .verdictFor(
              source: ProvenanceSource.json,
              externalId: 'callersbox:457',
              title: 'x',
            )
            .isNewDance,
        isTrue,
      );
    });
  });

  group('DedupeIndex fuzzy title + author', () {
    final index = DedupeIndex([
      DedupeEntry(
        danceId: 'd1',
        title: 'The Nice Combination',
        authorNames: ['Gene Hubert'],
      ),
      DedupeEntry(danceId: 'd2', title: 'Trip to Nowhere'),
    ]);

    test('titles that normalize to nothing never match each other', () {
      // `normalizeTitle` keeps only [a-z0-9], so every non-Latin or
      // punctuation-only title folds to ''. Two empty strings are equal, and
      // an equality short-circuit scored them 1.0 — so every such dance was
      // "ambiguous" against every other one (reviewer's red run:
      // `query "月" -> d1(花):1.000`), across scripts included.
      final nonLatin = DedupeIndex([
        DedupeEntry(danceId: 'd1', title: '花', authorNames: ['Alice Smith']),
        DedupeEntry(danceId: 'd2', title: 'Танец', authorNames: ['Bob Jones']),
        DedupeEntry(danceId: 'd3', title: '★'),
      ]);
      expect(
        nonLatin
            .verdictFor(
              source: ProvenanceSource.json,
              title: '月',
              authorNames: ['Alice Smith'],
            )
            .isNewDance,
        isTrue,
      );
      expect(
        nonLatin
            .verdictFor(source: ProvenanceSource.json, title: '★')
            .isNewDance,
        isTrue,
        reason: 'an empty normalized title carries no identity signal',
      );
      expect(nonLatin.fuzzyMatches('月', const []), isEmpty);
    });

    test('empty normalized titles never match, even at a near-zero threshold '
        'with shared authors', () {
      // `_similarity` scores an empty-vs-empty title 0.0, but
      // `_combinedScore` still blends in an author-only contribution when
      // both sides declare authors — 0.2 for a fully shared author set
      // here. A caller-supplied `threshold` of 0 (or as high as 0.2) would
      // then still surface the pair as a candidate despite the titles
      // carrying no identity signal at all. `fuzzyMatches` must skip an
      // empty-titled query or candidate before scoring, independent of how
      // `threshold` is tuned — never falling back to a fuzzy match on
      // authors alone.
      final nonLatin = DedupeIndex([
        DedupeEntry(danceId: 'd1', title: '花', authorNames: ['Alice Smith']),
      ]);
      expect(
        nonLatin.fuzzyMatches('月', ['Alice Smith'], threshold: 0),
        isEmpty,
      );
    });

    test('near-identical title is an ambiguous match', () {
      final v = index.verdictFor(
        source: ProvenanceSource.json,
        title: 'Nice Combination',
      );
      expect(v.isAmbiguous, isTrue);
      expect(v.candidates.first.danceId, 'd1');
      expect(v.candidates.first.score, greaterThan(0.72));
    });

    test('NFD title and author remain a confident match', () {
      final nfcIndex = DedupeIndex([
        DedupeEntry(danceId: 'd1', title: 'Résumé', authorNames: ['Chlöe']),
      ]);
      final v = nfcIndex.verdictFor(
        source: ProvenanceSource.json,
        title: 'Re\u0301sume\u0301',
        authorNames: ['Chlo\u0308e'],
        threshold: 0.99,
      );
      expect(v.isAmbiguous, isTrue);
      expect(v.hasConfidentMatch, isTrue);
      expect(v.candidates.single.danceId, 'd1');
    });

    test('unrelated title is new', () {
      final v = index.verdictFor(
        source: ProvenanceSource.json,
        title: 'Completely Unrelated Reel',
      );
      expect(v.isNewDance, isTrue);
    });

    test('author overlap boosts confidence on an exact-title tie', () {
      final withAuthor = index.fuzzyMatches('The Nice Combination', [
        'Gene Hubert',
      ]);
      final withoutAuthor = index.fuzzyMatches(
        'The Nice Combination',
        const [],
      );
      expect(withAuthor.first.score, greaterThanOrEqualTo(0.99));
      // With a full author match the score is at least as strong as title-only.
      expect(
        withAuthor.first.score,
        greaterThanOrEqualTo(withoutAuthor.first.score),
      );
    });

    test('missing author metadata never penalizes (title-only)', () {
      final v = index.fuzzyMatches('The Nice Combination', const []);
      expect(v.first.score, closeTo(1.0, 1e-9));
    });

    test('candidates are sorted best-first', () {
      final multi = DedupeIndex([
        DedupeEntry(danceId: 'a', title: 'Petronella Reel'),
        DedupeEntry(danceId: 'b', title: 'Petronella'),
      ]);
      final matches = multi.fuzzyMatches(
        'Petronella',
        const [],
        threshold: 0.5,
      );
      expect(matches.map((c) => c.danceId).first, 'b');
    });
  });

  group('DedupeResolution', () {
    test('link carries a target id', () {
      final r = DedupeResolution.link('d9');
      expect(r.kind, DedupeResolutionKind.link);
      expect(r.targetDanceId, 'd9');
    });

    test('duplicate and skip carry no target', () {
      expect(DedupeResolution.duplicate().targetDanceId, isNull);
      expect(DedupeResolution.skip().targetDanceId, isNull);
    });

    test('variation carries a target id, kind, and defaults linkBack to true '
        '(issue #686)', () {
      final r = DedupeResolution.variation('d9');
      expect(r.kind, DedupeResolutionKind.variation);
      expect(r.targetDanceId, 'd9');
      expect(r.linkBack, isTrue);
    });

    test('variation linkBack can be opted out', () {
      final r = DedupeResolution.variation('d9', linkBack: false);
      expect(r.linkBack, isFalse);
    });
  });

  group('confident match (issue #685)', () {
    // Simulates one source recording the pair as split into two authors
    // (e.g. Caller's Box's Authors[] array) while an incoming record from a
    // differently-tokenizing source (pre-#685 adapter behavior) only
    // resolves a partial / non-identical author set — the sets still
    // *intersect* even though they're not equal.
    final index = DedupeIndex([
      DedupeEntry(
        danceId: 'd1',
        title: 'The Nice Combination',
        authorNames: ['Alice Smith', 'Bob Jones'],
      ),
    ]);

    test('exact title + intersecting-but-not-identical author sets is '
        'confident even at an artificially high threshold', () {
      final matches = index.fuzzyMatches(
        'The Nice Combination',
        // Only partially overlapping: shares "Bob Jones", differs on the
        // other author (simulating mismatched tokenization upstream).
        ['Bob Jones', 'Robert Jones Jr.'],
        threshold: 0.95,
      );
      expect(matches, isNotEmpty);
      expect(matches.first.confident, isTrue);
    });

    test(
      'verdictFor never resolves an exact-title+shared-author pair to '
      'isNew, regardless of author-string formatting or threshold tuning',
      () {
        final v = index.verdictFor(
          source: ProvenanceSource.json,
          title: 'The Nice Combination',
          authorNames: ['Bob Jones', 'Robert Jones Jr.'],
          threshold: 0.95,
        );
        expect(v.isNewDance, isFalse);
        expect(v.isAmbiguous, isTrue);
        expect(v.hasConfidentMatch, isTrue);
      },
    );

    test('exact title + fully disjoint author sets is NOT confident', () {
      final matches = index.fuzzyMatches('The Nice Combination', ['Carol Lee']);
      // Score alone still surfaces this at the default threshold (title-only
      // weight dominates), but it must not be flagged confident.
      expect(matches, isNotEmpty);
      expect(matches.first.confident, isFalse);
    });

    test('no author overlap and no candidates at all means not confident', () {
      final noOverlapIndex = DedupeIndex([
        DedupeEntry(
          danceId: 'd1',
          title: 'Completely Different Title',
          authorNames: ['Carol Lee'],
        ),
      ]);
      final v = noOverlapIndex.verdictFor(
        source: ProvenanceSource.json,
        title: 'The Nice Combination',
        authorNames: ['Alice Smith'],
      );
      expect(v.isNewDance, isTrue);
      expect(v.hasConfidentMatch, isFalse);
    });

    test('title variance + author overlap is not "confident" (relies on the '
        'existing weighted score, unchanged) but Part A tokenization rescues '
        'it above threshold once authors correctly overlap', () {
      // A punctuation/article variance ("The" dropped) with authors that
      // now overlap post-tokenization: title similarity alone still clears
      // the default threshold once the (fixed) author signal contributes
      // positively rather than scoring a spurious 0.
      final v = index.verdictFor(
        source: ProvenanceSource.json,
        title: 'Nice Combination',
        authorNames: ['Alice Smith', 'Bob Jones'],
      );
      expect(v.isNewDance, isFalse);
      expect(v.isAmbiguous, isTrue);
    });
  });

  group('normalisation is precomputed', () {
    test('the index normalises each entry at construction', () {
      final index = DedupeIndex([
        DedupeEntry(
          danceId: 'd1',
          title: 'The Café  Réel!',
          authorNames: ['Zoë  O\'Brien', 'GENE Hubert', '★'],
        ),
        DedupeEntry(danceId: 'd2', title: 'An Ünïcode Reel'),
        DedupeEntry(danceId: 'd3', title: '花', authorNames: ['Alice']),
      ]);
      final byId = {
        for (final e in index.normalizedEntriesForTesting) e.danceId: e,
      };
      expect(byId['d1']!.normalizedTitle, 'cafe reel');
      expect(byId['d1']!.normalizedAuthors, {'zoe o brien', 'gene hubert'});
      expect(byId['d2']!.normalizedTitle, 'unicode reel');
      expect(byId['d2']!.normalizedAuthors, isEmpty);
      // Never scored: the empty title is kept (parallel to the entries) so the
      // loop can skip it without re-normalising.
      expect(byId['d3']!.normalizedTitle, isEmpty);
    });

    test('fuzzyMatches equals the per-entry re-normalising algorithm', () {
      const seed = 25;
      final rng = Random(seed);
      const words = [
        'the',
        'a',
        'an',
        'nice',
        'combination',
        'trip',
        'nowhere',
        'café',
        'reel',
        'jig',
        'ünï',
        'Ørsted',
        'swing',
        'star',
        "o'brien",
        'x-y',
        'hex',
        'ladies',
        'chain',
        'Zoë',
        'ñandú',
        '1,2,3',
        'sue',
        'sew',
      ];
      const odd = ['花', 'Танец', '★', '!!!', '', '   ', 'THE', 'A'];
      String title() {
        if (rng.nextInt(12) == 0) return odd[rng.nextInt(odd.length)];
        final n = 1 + rng.nextInt(4);
        return List.generate(
          n,
          (_) => words[rng.nextInt(words.length)],
        ).join(rng.nextBool() ? ' ' : '  ');
      }

      List<String> authors() => List.generate(
        rng.nextInt(4),
        (_) =>
            '${words[rng.nextInt(words.length)]} '
            '${words[rng.nextInt(words.length)]}',
      );

      final entries = [
        for (var i = 0; i < 200; i++)
          DedupeEntry(danceId: 'e$i', title: title(), authorNames: authors()),
      ];
      final index = DedupeIndex(entries);
      final queries = [
        for (var i = 0; i < 100; i++)
          // Half the queries are near-copies of an existing entry.
          if (i.isEven)
            (title(), authors())
          else
            (
              entries[rng.nextInt(entries.length)].title,
              entries[rng.nextInt(entries.length)].authorNames,
            ),
      ];
      for (final threshold in [0.0, 0.72, 1.0]) {
        for (final (t, a) in queries) {
          final expected = _referenceFuzzyMatches(entries, t, a, threshold);
          final actual = index.fuzzyMatches(t, a, threshold: threshold);
          final reason = 'seed=$seed threshold=$threshold query="$t" $a';
          expect(
            [for (final c in actual) c.danceId],
            [for (final c in expected) c.danceId],
            reason: reason,
          );
          expect(
            [for (final c in actual) c.score],
            [for (final c in expected) c.score],
            reason: reason,
          );
          expect(
            [for (final c in actual) c.confident],
            [for (final c in expected) c.confident],
            reason: reason,
          );
        }
      }
    });
  });

  group('length bound', () {
    test('never drops a pair the unbounded oracle keeps', () {
      final rng = Random(255);
      const alphabet = 'abcdef gh';
      // Lengths 1..60, skewed so many pairs differ a lot in length.
      String title() {
        final len = 1 + rng.nextInt(rng.nextBool() ? 8 : 60);
        return List.generate(
          len,
          (_) => alphabet[rng.nextInt(alphabet.length)],
        ).join();
      }

      List<String> authors() =>
          List.generate(rng.nextInt(3), (_) => 'au${rng.nextInt(4)}');

      final entries = [
        for (var i = 0; i < 300; i++)
          DedupeEntry(danceId: 'e$i', title: title(), authorNames: authors()),
      ];
      final index = DedupeIndex(entries);
      for (var q = 0; q < 150; q++) {
        final threshold = 0.5 + rng.nextDouble() * 0.5;
        final qTitle = q.isEven ? title() : entries[q].title;
        final qAuthors = authors();
        final got = index.fuzzyMatches(qTitle, qAuthors, threshold: threshold);
        final want = _referenceFuzzyMatches(
          entries,
          qTitle,
          qAuthors,
          threshold,
        );
        expect(
          [for (final c in got) (c.danceId, c.score, c.confident)],
          [for (final c in want) (c.danceId, c.score, c.confident)],
          reason: 'title "$qTitle" at $threshold',
        );
      }
    });

    test('an exact-title entry far below the threshold stays confident', () {
      final index = DedupeIndex([
        DedupeEntry(danceId: 'x', title: 'Same', authorNames: ['Ann']),
        DedupeEntry(danceId: 'y', title: 'Something Entirely Longer Than It'),
      ]);
      final hits = index.fuzzyMatches('same', ['ann'], threshold: 1.0);
      expect(hits.map((c) => c.danceId), ['x']);
      expect(hits.single.confident, isTrue);
    });
  });
}

/// The pre-precompute algorithm: re-normalises every entry on every query.
/// Oracle for the equivalence test; scoring helpers are verbatim copies.
List<DedupeCandidate> _referenceFuzzyMatches(
  List<DedupeEntry> entries,
  String title,
  Iterable<String> authorNames,
  double threshold,
) {
  final nTitle = normalizeTitle(title);
  final nAuthors = authorNames.map(normalizeAuthor).toSet()..remove('');
  if (nTitle.isEmpty) return const [];
  final out = <DedupeCandidate>[];
  for (final e in entries) {
    final eTitle = normalizeTitle(e.title);
    if (eTitle.isEmpty) continue;
    final eAuthors = e.authorNames.map(normalizeAuthor).toSet()..remove('');
    final titleSim = _refSimilarity(nTitle, eTitle);
    final score = nAuthors.isEmpty || eAuthors.isEmpty
        ? titleSim
        : titleSim * 0.8 + _refJaccard(nAuthors, eAuthors) * 0.2;
    final confident =
        nTitle.isNotEmpty &&
        nTitle == eTitle &&
        nAuthors.isNotEmpty &&
        eAuthors.isNotEmpty &&
        nAuthors.intersection(eAuthors).isNotEmpty;
    if (score >= threshold || confident) {
      out.add(
        DedupeCandidate(danceId: e.danceId, score: score, confident: confident),
      );
    }
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}

double _refJaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty && b.isEmpty) return 1.0;
  final inter = a.intersection(b).length;
  final union = a.union(b).length;
  return union == 0 ? 0.0 : inter / union;
}

double _refSimilarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0.0;
  if (a == b) return 1.0;
  final dist = _refLevenshtein(a, b);
  final maxLen = a.length > b.length ? a.length : b.length;
  return 1.0 - dist / maxLen;
}

int _refLevenshtein(String a, String b) {
  final prev = List<int>.generate(b.length + 1, (i) => i);
  final curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      var m = prev[j + 1] + 1;
      if (curr[j] + 1 < m) m = curr[j] + 1;
      if (prev[j] + cost < m) m = prev[j] + cost;
      curr[j + 1] = m;
    }
    for (var k = 0; k <= b.length; k++) {
      prev[k] = curr[k];
    }
  }
  return prev[b.length];
}
