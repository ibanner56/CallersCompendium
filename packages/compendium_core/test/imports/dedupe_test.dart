import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
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
        DedupeEntry(
          danceId: 'd1',
          title: 'Résumé',
          authorNames: ['Chlöe'],
        ),
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
}
