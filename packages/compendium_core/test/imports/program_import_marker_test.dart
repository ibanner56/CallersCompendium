import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  ProgramImportMarkerEntry entry({
    required String title,
    ProvenanceSource? source,
    String? externalId,
    DateTime? importedAt,
  }) => ProgramImportMarkerEntry(
    title: title,
    source: source,
    externalId: externalId,
    importedAt: importedAt,
  );

  final importedAt = DateTime.utc(2026, 5, 3, 12);

  group('strong (source, externalId) match → Imported', () {
    final index = ProgramImportMarkerIndex([
      entry(
        title: 'Spring Fling 2026',
        source: ProvenanceSource.contradb,
        externalId: '33',
        importedAt: importedAt,
      ),
    ]);

    test('exact ContraDB id match marks Imported with importedAt', () {
      final marker = index.markerFor('33', 'Spring Fling 2026');
      expect(marker.kind, ProgramImportMarkerKind.imported);
      expect(marker.isImported, isTrue);
      expect(marker.importedAt, importedAt);
    });

    test('id match wins even when the name differs (title irrelevant)', () {
      final marker = index.markerFor('33', 'A completely different name');
      expect(marker.kind, ProgramImportMarkerKind.imported);
    });

    test('non-matching id + non-matching title → none', () {
      final marker = index.markerFor('999', 'Nothing like it');
      expect(marker.kind, ProgramImportMarkerKind.none);
    });

    test('a different provenance source does not strong-match', () {
      final other = ProgramImportMarkerIndex([
        entry(
          title: 'Some Program',
          source: ProvenanceSource.callersCompanion,
          externalId: '33',
        ),
      ]);
      // Same id, but stored under a different source ⇒ no strong "Imported".
      expect(
        other.markerFor('33', 'Unrelated').kind,
        ProgramImportMarkerKind.none,
      );
    });
  });

  group('fuzzy title-only match → Possibly imported', () {
    final index = ProgramImportMarkerIndex([
      entry(title: 'The Nice Combination!'),
    ]);

    test(
      'normalized-equal title (case/punctuation/article) marks possible',
      () {
        final marker = index.markerFor('42', 'nice combination');
        expect(marker.kind, ProgramImportMarkerKind.possiblyImported);
        expect(marker.isPossiblyImported, isTrue);
        expect(marker.importedAt, isNull);
      },
    );

    test('non-equal title → none (no fuzzy over-matching)', () {
      expect(
        index.markerFor('42', 'Nice Combo').kind,
        ProgramImportMarkerKind.none,
      );
    });
  });

  group('no-provenance fallback', () {
    test('program without provenance still enables title-only match', () {
      final index = ProgramImportMarkerIndex([entry(title: 'Autumn Gala')]);
      // No stored id ⇒ id lookup misses, but the title still marks "possible".
      final marker = index.markerFor('7', 'autumn gala');
      expect(marker.kind, ProgramImportMarkerKind.possiblyImported);
    });
  });

  group('precedence imported > possiblyImported > none', () {
    test('id match takes precedence over a same-title fuzzy match', () {
      final index = ProgramImportMarkerIndex([
        entry(
          title: 'Barn Dance',
          source: ProvenanceSource.contradb,
          externalId: '10',
          importedAt: importedAt,
        ),
        // A second, hand-created program with the same title (no provenance).
        entry(title: 'Barn Dance'),
      ]);
      final marker = index.markerFor('10', 'Barn Dance');
      expect(marker.kind, ProgramImportMarkerKind.imported);
    });
  });

  group('security / input hardening', () {
    test('empty external id never strong-matches', () {
      final index = ProgramImportMarkerIndex([
        entry(
          title: 'Stored Title',
          source: ProvenanceSource.contradb,
          externalId: '5',
        ),
      ]);
      // Empty id can't strong-match; an unrelated query title stays none.
      expect(
        index.markerFor('', 'Unrelated Query').kind,
        ProgramImportMarkerKind.none,
      );
    });

    test('over-long external id cannot strong-match', () {
      final longId = '1' * 128;
      final index = ProgramImportMarkerIndex([
        entry(
          title: 'Stored Title',
          source: ProvenanceSource.contradb,
          externalId: longId,
        ),
      ]);
      // Even though a program stored this absurd id, a query for it is rejected
      // by the length cap before comparison; an unrelated title stays none.
      expect(
        index.markerFor(longId, 'Unrelated Query').kind,
        ProgramImportMarkerKind.none,
      );
    });

    test('over-long title is ignored for fuzzy matching', () {
      final longTitle = 'a' * 1000;
      final index = ProgramImportMarkerIndex([entry(title: longTitle)]);
      expect(
        index.markerFor('1', longTitle).kind,
        ProgramImportMarkerKind.none,
      );
    });

    test('whitespace-only / empty titles never match each other', () {
      final index = ProgramImportMarkerIndex([entry(title: '   ')]);
      expect(index.markerFor('1', '').kind, ProgramImportMarkerKind.none);
      expect(index.markerFor('1', '   ').kind, ProgramImportMarkerKind.none);
    });
  });
}
