import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 10);

  Dance make({
    String title = 'Butter',
    List<Figure> figures = const [],
    String phraseStructure = '',
  }) => Dance(
    id: 'd1',
    title: title,
    figures: figures,
    phraseStructure: phraseStructure,
    createdAt: now,
    updatedAt: now,
  );

  Figure fig(int beats) => Figure(move: 'swing', params: {'beats': beats});

  group('Dance invariants', () {
    test('rejects empty or whitespace-only titles', () {
      expect(() => make(title: ''), throwsArgumentError);
      expect(() => make(title: '  \t'), throwsArgumentError);
    });

    test('allows an empty figure list (metadata-only stub)', () {
      expect(make().figures, isEmpty);
    });

    test('rejects unparseable phrase structures at construction', () {
      expect(() => make(phraseStructure: 'nonsense'), throwsFormatException);
    });

    test('collections are unmodifiable', () {
      final d = make(figures: [fig(8)]);
      expect(() => d.figures.add(fig(8)), throwsUnsupportedError);
      expect(() => d.authorIds.add('x'), throwsUnsupportedError);
      expect(() => d.tunes.add('x'), throwsUnsupportedError);
      expect(() => d.tagIds.add('x'), throwsUnsupportedError);
    });

    test('sensible contra defaults', () {
      final d = make();
      expect(d.form, DanceForm.contra);
      expect(d.formation.shape, FormationShape.dupleImproper);
      expect(d.progression, Progression.single);
      expect(d.phraseStructure, PhraseStructure.standard);
      expect(d.status, DanceStatus.active);
      expect(d.isDeleted, isFalse);
    });
  });

  group('Dance.validate', () {
    test('exact-fit figures produce no issues', () {
      expect(make(figures: [fig(32), fig(32)]).validate(), isEmpty);
    });

    test('overflow surfaces as a warning', () {
      final issues = make(figures: [fig(64), fig(8)]).validate();
      expect(issues.single.severity, ValidationSeverity.warning);
      expect(issues.single.code, 'phrase_overflow');
    });

    test('validates against a non-standard phrase structure', () {
      // 96-beat dance in a 6*8*2 structure: exact fit, no issues.
      expect(
        make(figures: [fig(48), fig(48)], phraseStructure: '6*8*2').validate(),
        isEmpty,
      );
    });
  });

  group('sectionedFigures', () {
    test('labels follow the dance phrase structure', () {
      final d = make(figures: [fig(16), fig(16), fig(16), fig(16)]);
      expect(d.sectionedFigures.map((s) => s.label), ['A1', 'A2', 'B1', 'B2']);
    });
  });

  group('soft delete', () {
    test('copyWith sets and clearDeletedAt restores', () {
      final deleted = make().copyWith(deletedAt: now);
      expect(deleted.isDeleted, isTrue);
      final restored = deleted.copyWith(clearDeletedAt: true);
      expect(restored.isDeleted, isFalse);
    });
  });

  group('duplicate', () {
    test('copies content with fresh identity and drops provenance', () {
      final original = Dance(
        id: 'd1',
        title: 'Butter',
        authorIds: ['c1'],
        figures: [fig(64)],
        hook: 'everyone loves it',
        tunes: ['Batter Up'],
        provenance: Provenance(
          source: ProvenanceSource.callersbox,
          externalId: '123',
          importedAt: now,
        ),
        createdAt: now.subtract(const Duration(days: 400)),
        updatedAt: now.subtract(const Duration(days: 30)),
      );
      final later = now.add(const Duration(days: 1));
      final copy = original.duplicate(newId: 'd2', now: later);
      expect(copy.id, 'd2');
      expect(copy.title, original.title);
      expect(copy.figures, original.figures);
      expect(copy.authorIds, original.authorIds);
      expect(copy.provenance, isNull);
      expect(copy.createdAt, later);
      expect(copy.updatedAt, later);
    });
  });

  group('value equality', () {
    test('identical content compares equal', () {
      expect(make(figures: [fig(8)]), equals(make(figures: [fig(8)])));
    });

    test('differing figures compare unequal', () {
      expect(make(figures: [fig(8)]), isNot(equals(make(figures: [fig(16)]))));
    });
  });
}
