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

    test('regenerates link ids so a persisted copy cannot collide', () {
      final original = Dance(
        id: 'd1',
        title: 'Butter',
        links: [
          DanceLink(id: 'link-1', kind: LinkKind.video, url: 'https://v'),
          DanceLink(id: 'link-2', kind: LinkKind.source, url: 'https://s'),
        ],
        createdAt: now,
        updatedAt: now,
      );
      var counter = 0;
      final copy = original.duplicate(
        newId: 'd2',
        now: now,
        newLinkId: () => 'new-${counter++}',
      );
      // Fresh ids …
      expect(copy.links.map((l) => l.id), ['new-0', 'new-1']);
      // … but the rest of each link is preserved.
      expect(copy.links[0].kind, LinkKind.video);
      expect(copy.links[0].url, 'https://v');
      expect(copy.links[1].kind, LinkKind.source);
      expect(copy.links[1].url, 'https://s');
    });

    test('preserves a related-dance link target while regenerating its id', () {
      final original = Dance(
        id: 'd1',
        title: 'Butter',
        links: [
          DanceLink(
            id: 'link-1',
            kind: LinkKind.relatedDance,
            targetDanceId: 'other',
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final copy = original.duplicate(
        newId: 'd2',
        now: now,
        newLinkId: () => 'fresh',
      );
      expect(copy.links.single.id, 'fresh');
      expect(copy.links.single.kind, LinkKind.relatedDance);
      expect(copy.links.single.targetDanceId, 'other');
    });

    test('default id generator yields unique link ids', () {
      final original = Dance(
        id: 'd1',
        title: 'Butter',
        links: [
          DanceLink(id: 'link-1', kind: LinkKind.video, url: 'https://v'),
          DanceLink(id: 'link-2', kind: LinkKind.source, url: 'https://s'),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final copy = original.duplicate(newId: 'd2', now: now);
      final ids = copy.links.map((l) => l.id).toSet();
      expect(ids.length, 2);
      expect(ids, isNot(contains('link-1')));
      expect(ids, isNot(contains('link-2')));
    });
  });

  group('value equality', () {
    test('identical content compares equal', () {
      expect(make(figures: [fig(8)]), equals(make(figures: [fig(8)])));
    });

    test('differing figures compare unequal', () {
      expect(make(figures: [fig(8)]), isNot(equals(make(figures: [fig(16)]))));
    });

    test('differing composed/revised dates compare unequal', () {
      final base = make();
      expect(
        base.copyWith(composedOn: PartialDate(1989)),
        isNot(equals(base.copyWith(composedOn: PartialDate(1990)))),
      );
      expect(
        base.copyWith(composedOn: PartialDate(1989)),
        equals(base.copyWith(composedOn: PartialDate(1989))),
      );
    });
  });

  group('composed / revised dates', () {
    test('copyWith sets values and clear flags reset them', () {
      final d = make().copyWith(
        composedOn: PartialDate(1989),
        revisedOn: PartialDate(2004, 3, 15),
      );
      expect(d.composedOn, PartialDate(1989));
      expect(d.revisedOn, PartialDate(2004, 3, 15));

      final clearedComposed = d.copyWith(clearComposedOn: true);
      expect(clearedComposed.composedOn, isNull);
      expect(clearedComposed.revisedOn, PartialDate(2004, 3, 15));

      final clearedRevised = d.copyWith(clearRevisedOn: true);
      expect(clearedRevised.revisedOn, isNull);
      expect(clearedRevised.composedOn, PartialDate(1989));
    });

    test('a set clear flag wins over a value for the same field', () {
      final d = make().copyWith(composedOn: PartialDate(1989));
      final result = d.copyWith(
        composedOn: PartialDate(2020),
        clearComposedOn: true,
      );
      expect(result.composedOn, isNull);
    });

    test('duplicate carries both dates through', () {
      final original = make().copyWith(
        composedOn: PartialDate(1989),
        revisedOn: PartialDate(2004, 3),
      );
      final copy = original.duplicate(newId: 'd2', now: now);
      expect(copy.composedOn, PartialDate(1989));
      expect(copy.revisedOn, PartialDate(2004, 3));
    });

    test('validate warns (never throws) when revised precedes composed', () {
      final d = make().copyWith(
        composedOn: PartialDate(2004),
        revisedOn: PartialDate(1989),
      );
      final issues = d.validate();
      expect(
        issues.where((i) => i.code == 'revised_before_composed'),
        hasLength(1),
      );
      expect(
        issues.firstWhere((i) => i.code == 'revised_before_composed').severity,
        ValidationSeverity.warning,
      );
    });

    test('validate is silent when revised is on/after composed', () {
      expect(
        make()
            .copyWith(
              composedOn: PartialDate(1989),
              revisedOn: PartialDate(2004),
            )
            .validate()
            .where((i) => i.code == 'revised_before_composed'),
        isEmpty,
      );
      // Only one of the two present → no comparison, no warning.
      expect(
        make()
            .copyWith(composedOn: PartialDate(1989))
            .validate()
            .where((i) => i.code == 'revised_before_composed'),
        isEmpty,
      );
    });

    test('validate does not warn on overlapping partial precisions', () {
      // composed 1989-03 vs revised 1989 (year-only): the revision could
      // plausibly be later in 1989, so this is not a definite inversion.
      expect(
        make()
            .copyWith(
              composedOn: PartialDate(1989, 3),
              revisedOn: PartialDate(1989),
            )
            .validate()
            .where((i) => i.code == 'revised_before_composed'),
        isEmpty,
      );
    });
  });

  group('rating', () {
    test('accepts null (unrated) and every in-range 1..5 value', () {
      expect(make().rating, isNull);
      for (final r in [1, 2, 3, 4, 5]) {
        expect(make().copyWith(rating: r).rating, r);
      }
    });

    test('rejects out-of-range ratings at construction', () {
      for (final bad in [0, 6, -1, 100]) {
        expect(() => make().copyWith(rating: bad), throwsArgumentError);
      }
    });

    test('copyWith sets a value and clearRating resets it', () {
      final rated = make().copyWith(rating: 4);
      expect(rated.rating, 4);
      expect(rated.copyWith(clearRating: true).rating, isNull);
    });

    test('a set clear flag wins over a value for the same field', () {
      final d = make().copyWith(rating: 3);
      expect(d.copyWith(rating: 5, clearRating: true).rating, isNull);
    });

    test('== distinguishes differing ratings', () {
      final base = make();
      expect(base.copyWith(rating: 4), isNot(equals(base.copyWith(rating: 5))));
      expect(base.copyWith(rating: 4), equals(base.copyWith(rating: 4)));
    });

    test('duplicate carries the rating through', () {
      final original = make().copyWith(rating: 5);
      final copy = original.duplicate(newId: 'd2', now: now);
      expect(copy.rating, 5);
    });
  });
}
