import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('normalization', () {
    test('title folds case, punctuation, diacritics, articles', () {
      expect(normalizeTitle('The Nice Combination!'), 'nice combination');
      expect(normalizeTitle('Café Béguine'), 'cafe beguine');
      expect(normalizeTitle('  A  Fine   Romance  '), 'fine romance');
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
  });
}
