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
  final noteField = CustomFieldDef(
    id: 'note',
    key: 'notes',
    label: 'Notes',
    type: CustomFieldType.text,
    searchable: true,
  );
  final levelField = CustomFieldDef(
    id: 'level',
    key: 'diffLevel',
    label: 'Difficulty level',
    type: CustomFieldType.number,
    searchable: true,
  );
  final defs = [tagField, flagField, noteField, levelField];

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

    test('a single level facet yields a LevelFilter(eq) leaf', () {
      final facets = FacetSelections()..levels.add(DanceLevel.intermediate);
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      expect(f, isA<LevelFilter>());
      final l = f as LevelFilter;
      expect(l.level, DanceLevel.intermediate);
      expect(l.op, LevelOp.eq);
    });

    test('multiple levels OR within the level facet', () {
      final facets = FacetSelections()
        ..levels.addAll({DanceLevel.beginner, DanceLevel.advanced});
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      expect(f, isA<OrFilter>());
      final levels = (f as OrFilter).children.whereType<LevelFilter>().toList();
      expect(levels.map((l) => l.level).toSet(), {
        DanceLevel.beginner,
        DanceLevel.advanced,
      });
      expect(levels.every((l) => l.op == LevelOp.eq), isTrue);
    });

    test('mixedLevel facet yields a MixedLevelFilter', () {
      final facets = FacetSelections()..mixedLevel = true;
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      expect(f, isA<MixedLevelFilter>());
      expect((f as MixedLevelFilter).mixed, isTrue);
    });

    test('minRating facet yields a RatingFilter with the chosen floor', () {
      final facets = FacetSelections()..minRating = 4;
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      expect(f, isA<RatingFilter>());
      expect((f as RatingFilter).minimum, 4);
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

    test(
      'text contains facet composes a CustomFieldFilter with contains op',
      () {
        final facets = FacetSelections();
        facets.textValues['note'] = const TextFacetState(
          op: CustomFieldOp.contains,
          value: 'petronella',
        );
        final f = buildCollectionFilter(
          ftsText: '',
          facets: facets,
          defs: defs,
        );
        expect(f, isA<CustomFieldFilter>());
        final cf = f as CustomFieldFilter;
        expect(cf.op, CustomFieldOp.contains);
        expect(cf.value, 'petronella');
      },
    );

    test('text equals facet composes a CustomFieldFilter with equals op', () {
      final facets = FacetSelections();
      facets.textValues['note'] = const TextFacetState(
        op: CustomFieldOp.equals,
        value: 'exact',
      );
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      expect(f, isA<CustomFieldFilter>());
      final cf = f as CustomFieldFilter;
      expect(cf.op, CustomFieldOp.equals);
      expect(cf.value, 'exact');
    });

    test('empty text facet value is skipped', () {
      final facets = FacetSelections();
      facets.textValues['note'] = const TextFacetState(
        op: CustomFieldOp.contains,
        value: '  ',
      );
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      // Empty value → skipped → match-all
      expect(f, isA<AndFilter>());
      expect((f as AndFilter).children, isEmpty);
    });

    test('number eq facet composes a CustomFieldFilter with eq op', () {
      final facets = FacetSelections();
      facets.numberValues['level'] = const NumberFacetState(
        op: CustomFieldOp.eq,
        lo: 3,
      );
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      expect(f, isA<CustomFieldFilter>());
      final cf = f as CustomFieldFilter;
      expect(cf.op, CustomFieldOp.eq);
      expect(cf.value, 3);
    });

    test('number lt facet composes a CustomFieldFilter with lt op', () {
      final facets = FacetSelections();
      facets.numberValues['level'] = const NumberFacetState(
        op: CustomFieldOp.lt,
        lo: 5,
      );
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      final cf = f as CustomFieldFilter;
      expect(cf.op, CustomFieldOp.lt);
      expect(cf.value, 5);
    });

    test('number gt facet composes a CustomFieldFilter with gt op', () {
      final facets = FacetSelections();
      facets.numberValues['level'] = const NumberFacetState(
        op: CustomFieldOp.gt,
        lo: 2,
      );
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      final cf = f as CustomFieldFilter;
      expect(cf.op, CustomFieldOp.gt);
      expect(cf.value, 2);
    });

    test('number between facet composes a [lo, hi] CustomFieldFilter', () {
      final facets = FacetSelections();
      facets.numberValues['level'] = const NumberFacetState(
        op: CustomFieldOp.between,
        lo: 2,
        hi: 7,
      );
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      expect(f, isA<CustomFieldFilter>());
      final cf = f as CustomFieldFilter;
      expect(cf.op, CustomFieldOp.between);
      expect(cf.value, [2, 7]);
    });

    test('incomplete between (hi is null) is skipped', () {
      final facets = FacetSelections();
      facets.numberValues['level'] = const NumberFacetState(
        op: CustomFieldOp.between,
        lo: 2,
      );
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      // Incomplete between → skipped → match-all
      expect(f, isA<AndFilter>());
      expect((f as AndFilter).children, isEmpty);
    });

    test('text facet ANDs with a form facet', () {
      final facets = FacetSelections()..forms.add(DanceForm.contra);
      facets.textValues['note'] = const TextFacetState(
        op: CustomFieldOp.contains,
        value: 'swing',
      );
      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: defs);
      expect(f, isA<AndFilter>());
      final children = (f as AndFilter).children;
      expect(children.whereType<FormFilter>(), hasLength(1));
      expect(children.whereType<CustomFieldFilter>(), hasLength(1));
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

    test('false when a text custom-field facet is active', () {
      final facets = FacetSelections();
      facets.textValues['note'] = const TextFacetState(
        op: CustomFieldOp.contains,
        value: 'swing',
      );
      expect(isBareFullText(ftsText: 'swing', facets: facets), isFalse);
    });

    test('false when a number custom-field facet is active', () {
      final facets = FacetSelections();
      facets.numberValues['level'] = const NumberFacetState(
        op: CustomFieldOp.eq,
        lo: 3,
      );
      expect(isBareFullText(ftsText: 'swing', facets: facets), isFalse);
    });

    // --- effective-facet correctness (fix for isEmpty / isBareFullText) -----

    test(
      'whitespace-only text facet is NOT counted as active (isEmpty = true)',
      () {
        final facets = FacetSelections();
        facets.textValues['note'] = const TextFacetState(
          op: CustomFieldOp.contains,
          value: '   ',
        );
        expect(facets.isEmpty, isTrue);
      },
    );

    test('non-empty text facet IS counted as active (isEmpty = false)', () {
      final facets = FacetSelections();
      facets.textValues['note'] = const TextFacetState(
        op: CustomFieldOp.contains,
        value: 'swing',
      );
      expect(facets.isEmpty, isFalse);
    });

    test('between with no hi is NOT counted as active (isEmpty = true for '
        'number facet)', () {
      final facets = FacetSelections();
      facets.numberValues['level'] = const NumberFacetState(
        op: CustomFieldOp.between,
        lo: 2,
      );
      expect(facets.isEmpty, isTrue);
    });

    test('complete between IS counted as active (isEmpty = false)', () {
      final facets = FacetSelections();
      facets.numberValues['level'] = const NumberFacetState(
        op: CustomFieldOp.between,
        lo: 2,
        hi: 7,
      );
      expect(facets.isEmpty, isFalse);
    });

    test('level and mixedLevel facets count toward isEmpty', () {
      final withLevel = FacetSelections()..levels.add(DanceLevel.beginner);
      expect(withLevel.isEmpty, isFalse);
      final withMixed = FacetSelections()..mixedLevel = true;
      expect(withMixed.isEmpty, isFalse);
    });

    test('minRating facet counts toward isEmpty and clear() resets it', () {
      final facets = FacetSelections()..minRating = 3;
      expect(facets.isEmpty, isFalse);
      facets.clear();
      expect(facets.minRating, isNull);
      expect(facets.isEmpty, isTrue);
    });

    test('clear() resets level and mixedLevel facets', () {
      final facets = FacetSelections()
        ..levels.add(DanceLevel.advanced)
        ..mixedLevel = false;
      expect(facets.isEmpty, isFalse);
      facets.clear();
      expect(facets.levels, isEmpty);
      expect(facets.mixedLevel, isNull);
      expect(facets.isEmpty, isTrue);
    });

    test(
      'isBareFullText is true when the only facets present are '
      'whitespace-only text and incomplete between (neither is effective)',
      () {
        final facets = FacetSelections();
        facets.textValues['note'] = const TextFacetState(
          op: CustomFieldOp.contains,
          value: '  ',
        );
        facets.numberValues['level'] = const NumberFacetState(
          op: CustomFieldOp.between,
          lo: 2,
        );
        expect(isBareFullText(ftsText: 'swing', facets: facets), isTrue);
      },
    );
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

  group('BuilderFigureGroup folding', () {
    test('empty group folds to null', () {
      expect(BuilderFigureGroup().toFigureQuery(), isNull);
    });

    test('all-of yields FigureAnd', () {
      final all = BuilderFigureGroup(
        kind: GroupKind.all,
        children: [
          BuilderFigure(move: 'swing'),
          BuilderFigure(move: 'balance'),
        ],
      );
      expect(all.toFigureQuery(), isA<FigureAnd>());
    });

    test('any-of yields FigureOr', () {
      final any = BuilderFigureGroup(
        kind: GroupKind.any,
        children: [
          BuilderFigure(move: 'swing'),
          BuilderFigure(move: 'balance'),
        ],
      );
      expect(any.toFigureQuery(), isA<FigureOr>());
    });

    test('none-of wraps FigureOr in FigureNot', () {
      final none = BuilderFigureGroup(
        kind: GroupKind.none,
        children: [
          BuilderFigure(move: 'swing'),
          BuilderFigure(move: 'balance'),
        ],
      );
      final q = none.toFigureQuery();
      expect(q, isA<FigureNot>());
      expect((q as FigureNot).child, isA<FigureOr>());
    });

    test('single-child group unwraps the redundant combinator', () {
      final single = BuilderFigureGroup(
        kind: GroupKind.any,
        children: [BuilderFigure(move: 'swing')],
      );
      // One effective child → no wrapping OR, just the leaf
      expect(single.toFigureQuery(), isA<FigureLeaf>());
      expect((single.toFigureQuery()! as FigureLeaf).move, 'swing');
    });

    test('single none-of child wraps in FigureNot(FigureLeaf)', () {
      final none = BuilderFigureGroup(
        kind: GroupKind.none,
        children: [BuilderFigure(move: 'chain')],
      );
      final q = none.toFigureQuery();
      expect(q, isA<FigureNot>());
      expect((q as FigureNot).child, isA<FigureLeaf>());
      expect(((q).child as FigureLeaf).move, 'chain');
    });

    test('incomplete figure children are skipped', () {
      final group = BuilderFigureGroup(
        kind: GroupKind.any,
        children: [
          BuilderFigure(), // incomplete — no move
          BuilderFigure(move: 'swing'),
        ],
      );
      // Skips incomplete → one effective child → unwraps to FigureLeaf
      final q = group.toFigureQuery();
      expect(q, isA<FigureLeaf>());
      expect((q! as FigureLeaf).move, 'swing');
    });

    test('all-incomplete children fold to null', () {
      final group = BuilderFigureGroup(
        kind: GroupKind.any,
        children: [BuilderFigure(), BuilderFigure()],
      );
      expect(group.toFigureQuery(), isNull);
    });

    test('FigureOr children contain the correct moves', () {
      final group = BuilderFigureGroup(
        kind: GroupKind.any,
        children: [
          BuilderFigure(move: 'swing'),
          BuilderFigure(move: 'balance'),
          BuilderFigure(move: 'petronella'),
        ],
      );
      final q = group.toFigureQuery() as FigureOr;
      final moves = q.children.cast<FigureLeaf>().map((l) => l.move).toSet();
      expect(moves, {'swing', 'balance', 'petronella'});
    });

    test('nested BuilderFigureGroup folds recursively', () {
      final inner = BuilderFigureGroup(
        kind: GroupKind.any,
        children: [
          BuilderFigure(move: 'swing'),
          BuilderFigure(move: 'balance'),
        ],
      );
      final outer = BuilderFigureGroup(
        kind: GroupKind.all,
        children: [
          inner,
          BuilderFigure(move: 'chain'),
        ],
      );
      final q = outer.toFigureQuery();
      expect(q, isA<FigureAnd>());
      final andChildren = (q as FigureAnd).children;
      expect(andChildren, hasLength(2));
      expect(andChildren.first, isA<FigureOr>());
      expect(andChildren.last, isA<FigureLeaf>());
    });
  });

  group('BuilderThen with figure groups', () {
    test(
      'before=group(any), after=leaf folds to ThenFilter(FigureOr, FigureLeaf)',
      () {
        final thenNode = BuilderThen(
          before: BuilderFigureGroup(
            kind: GroupKind.any,
            children: [
              BuilderFigure(move: 'swing'),
              BuilderFigure(move: 'balance'),
            ],
          ),
          after: BuilderFigure(move: 'chain'),
        );
        final f = thenNode.toFilter();
        expect(f, isA<ThenFilter>());
        final tf = f as ThenFilter;
        expect(tf.before, isA<FigureOr>());
        expect(tf.after, isA<FigureLeaf>());
        expect((tf.after as FigureLeaf).move, 'chain');
        final orMoves = (tf.before as FigureOr).children
            .cast<FigureLeaf>()
            .map((l) => l.move)
            .toSet();
        expect(orMoves, {'swing', 'balance'});
      },
    );

    test(
      'before=leaf, after=none-of-group folds to ThenFilter(FigureLeaf, FigureNot)',
      () {
        final thenNode = BuilderThen(
          before: BuilderFigure(move: 'petronella'),
          after: BuilderFigureGroup(
            kind: GroupKind.none,
            children: [BuilderFigure(move: 'chain')],
          ),
        );
        final f = thenNode.toFilter();
        expect(f, isA<ThenFilter>());
        final tf = f as ThenFilter;
        expect(tf.before, isA<FigureLeaf>());
        expect((tf.before as FigureLeaf).move, 'petronella');
        expect(tf.after, isA<FigureNot>());
        // none-of with one child → FigureNot(FigureLeaf)
        expect((tf.after as FigureNot).child, isA<FigureLeaf>());
        expect(((tf.after as FigureNot).child as FigureLeaf).move, 'chain');
      },
    );

    test('both operands groups: any-of before, none-of after', () {
      final thenNode = BuilderThen(
        before: BuilderFigureGroup(
          kind: GroupKind.any,
          children: [
            BuilderFigure(move: 'swing'),
            BuilderFigure(move: 'balance'),
          ],
        ),
        after: BuilderFigureGroup(
          kind: GroupKind.none,
          children: [
            BuilderFigure(move: 'chain'),
            BuilderFigure(move: 'hey'),
          ],
        ),
      );
      final f = thenNode.toFilter();
      expect(f, isA<ThenFilter>());
      final tf = f as ThenFilter;
      expect(tf.before, isA<FigureOr>());
      expect(tf.after, isA<FigureNot>());
      expect((tf.after as FigureNot).child, isA<FigureOr>());
      final notOrMoves = ((tf.after as FigureNot).child as FigureOr).children
          .cast<FigureLeaf>()
          .map((l) => l.move)
          .toSet();
      expect(notOrMoves, {'chain', 'hey'});
    });

    test('before=group with all-incomplete children, after=leaf → null', () {
      final thenNode = BuilderThen(
        before: BuilderFigureGroup(
          kind: GroupKind.any,
          children: [BuilderFigure(), BuilderFigure()], // all incomplete
        ),
        after: BuilderFigure(move: 'chain'),
      );
      expect(thenNode.toFilter(), isNull);
    });

    test(
      'before=group(all-of), after=leaf folds to ThenFilter(FigureAnd, FigureLeaf)',
      () {
        final thenNode = BuilderThen(
          before: BuilderFigureGroup(
            kind: GroupKind.all,
            children: [
              BuilderFigure(move: 'swing', section: 'B1'),
              BuilderFigure(move: 'circle'),
            ],
          ),
          after: BuilderFigure(move: 'star'),
        );
        final f = thenNode.toFilter();
        expect(f, isA<ThenFilter>());
        final tf = f as ThenFilter;
        expect(tf.before, isA<FigureAnd>());
        expect((tf.before as FigureAnd).children, hasLength(2));
      },
    );
  });
}
