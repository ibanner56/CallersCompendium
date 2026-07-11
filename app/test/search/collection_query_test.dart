import 'package:compendium_app/src/search/collection_query.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tagField = CustomFieldDef(
    id: 'diff',
    key: 'difficulty',
    label: 'Difficulty',
    type: CustomFieldType.choice,
    choices: const ['easy', 'hard'],
  );
  final flagField = CustomFieldDef(
    id: 'teach',
    key: 'needsTeaching',
    label: 'Needs teaching',
    type: CustomFieldType.boolean,
  );
  final defs = [tagField, flagField];

  group('buildCollectionFilter', () {
    test('empty query matches everything (AndFilter([]))', () {
      final f = buildCollectionFilter(
        ftsText: '',
        facets: FacetSelections(),
        defs: defs,
      );
      expect(f, isA<AndFilter>());
      expect((f as AndFilter).children, isEmpty);
    });

    test('full-text only yields a bare FullTextFilter', () {
      final f = buildCollectionFilter(
        ftsText: '  petronella  ',
        facets: FacetSelections(),
        defs: defs,
      );
      expect(f, isA<FullTextFilter>());
      expect((f as FullTextFilter).query, 'petronella');
    });

    test('a single facet yields a single leaf', () {
      final facets = FacetSelections()..forms.add(DanceForm.contra);
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      expect(f, isA<FormFilter>());
      expect((f as FormFilter).form, DanceForm.contra);
    });

    test('different facets AND together', () {
      final facets = FacetSelections()
        ..forms.add(DanceForm.contra)
        ..tagIds.add('t1');
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      expect(f, isA<AndFilter>());
      final children = (f as AndFilter).children;
      expect(children.whereType<FormFilter>(), hasLength(1));
      expect(children.whereType<TagFilter>(), hasLength(1));
    });

    test('multiple tags OR within the tag facet', () {
      final facets = FacetSelections()..tagIds.addAll(['t1', 't2']);
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      expect(f, isA<OrFilter>());
      final tags = (f as OrFilter).children.whereType<TagFilter>().toList();
      expect(tags.map((t) => t.tagId).toSet(), {'t1', 't2'});
    });

    test('fts + facets compose into a flat AndFilter', () {
      final facets = FacetSelections()
        ..formations.add(FormationShape.becketCw)
        ..tagIds.addAll(['t1', 't2']);
      final f = buildCollectionFilter(
        ftsText: 'swing',
        facets: facets,
        defs: defs,
      );
      expect(f, isA<AndFilter>());
      final children = (f as AndFilter).children;
      expect(children.whereType<FullTextFilter>(), hasLength(1));
      expect(children.whereType<FormationFilter>(), hasLength(1));
      // The two tags collapse into one OR branch.
      expect(children.whereType<OrFilter>(), hasLength(1));
    });

    test('choice custom field ORs selected values', () {
      final facets = FacetSelections();
      facets.choiceValues['diff'] = {'easy', 'hard'};
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      expect(f, isA<OrFilter>());
      final leaves = (f as OrFilter).children.cast<CustomFieldFilter>();
      expect(leaves.map((l) => l.value).toSet(), {'easy', 'hard'});
      expect(leaves.every((l) => l.op == CustomFieldOp.is_), isTrue);
    });

    test('boolean custom field is a single is_ leaf', () {
      final facets = FacetSelections();
      facets.booleanValues['teach'] = true;
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      expect(f, isA<CustomFieldFilter>());
      expect((f as CustomFieldFilter).value, true);
    });

    test('advanced tree ANDs onto the facet leaves', () {
      final facets = FacetSelections()..forms.add(DanceForm.contra);
      final root = BuilderGroup(children: [BuilderFigure(move: 'swing')]);
      final f = buildCollectionFilter(
        ftsText: '',
        facets: facets,
        defs: defs,
        advancedRoot: root,
      );
      expect(f, isA<AndFilter>());
      final children = (f as AndFilter).children;
      expect(children.whereType<FormFilter>(), hasLength(1));
      expect(children.whereType<FigureFilter>(), hasLength(1));
    });
  });

  group('isBareFullText', () {
    test('true for text with no facets/advanced', () {
      expect(
        isBareFullText(ftsText: 'swing', facets: FacetSelections()),
        isTrue,
      );
    });

    test('false when a facet is selected', () {
      final facets = FacetSelections()..forms.add(DanceForm.contra);
      expect(isBareFullText(ftsText: 'swing', facets: facets), isFalse);
    });

    test('false when the text is empty', () {
      expect(
        isBareFullText(ftsText: '   ', facets: FacetSelections()),
        isFalse,
      );
    });

    test('false when an advanced condition is present', () {
      final root = BuilderGroup(children: [BuilderFigure(move: 'swing')]);
      expect(
        isBareFullText(
          ftsText: 'swing',
          facets: FacetSelections(),
          advancedRoot: root,
        ),
        isFalse,
      );
    });
  });

  group('BuilderGroup folding', () {
    test('empty group folds to null', () {
      expect(BuilderGroup().toFilter(), isNull);
    });

    test('all-of yields AndFilter, any-of OrFilter', () {
      final all = BuilderGroup(
        kind: GroupKind.all,
        children: [
          BuilderFigure(move: 'swing'),
          BuilderFigure(move: 'balance'),
        ],
      );
      expect(all.toFilter(), isA<AndFilter>());

      final any = BuilderGroup(
        kind: GroupKind.any,
        children: [
          BuilderFigure(move: 'swing'),
          BuilderFigure(move: 'balance'),
        ],
      );
      expect(any.toFilter(), isA<OrFilter>());
    });

    test('none-of wraps the OR of children in a NotFilter', () {
      final none = BuilderGroup(
        kind: GroupKind.none,
        children: [
          BuilderFigure(move: 'swing'),
          BuilderFigure(move: 'balance'),
        ],
      );
      final f = none.toFilter();
      expect(f, isA<NotFilter>());
      expect((f as NotFilter).child, isA<OrFilter>());
    });

    test('a single-child group unwraps the redundant combinator', () {
      final all = BuilderGroup(
        kind: GroupKind.all,
        children: [BuilderFigure(move: 'swing')],
      );
      expect(all.toFilter(), isA<FigureFilter>());
    });

    test('incomplete figure rows are skipped', () {
      final group = BuilderGroup(
        children: [
          BuilderFigure(),
          BuilderFigure(move: 'swing'),
        ],
      );
      expect(group.toFilter(), isA<FigureFilter>());
    });
  });

  group('BuilderFigure / BuilderThen', () {
    test('figure with move, section and params folds to a FigureFilter', () {
      final fig = BuilderFigure(
        move: 'swing',
        section: 'B1',
        params: {'who': 'partners'},
      );
      final f = fig.toFilter();
      expect(f, isA<FigureFilter>());
      final query = (f as FigureFilter).query as FigureLeaf;
      expect(query.move, 'swing');
      expect(query.section, 'B1');
      expect(query.params['who'], 'partners');
    });

    test('figure without a move folds to null', () {
      expect(BuilderFigure(section: 'A1').toFilter(), isNull);
    });

    test('then needs both operands complete', () {
      final incomplete = BuilderThen(before: BuilderFigure(move: 'swing'));
      expect(incomplete.toFilter(), isNull);

      final complete = BuilderThen(
        before: BuilderFigure(move: 'petronella'),
        after: BuilderFigure(move: 'swing'),
      );
      final f = complete.toFilter();
      expect(f, isA<ThenFilter>());
      expect(((f as ThenFilter).before as FigureLeaf).move, 'petronella');
      expect((f.after as FigureLeaf).move, 'swing');
    });
  });
}
