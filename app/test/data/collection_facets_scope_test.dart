import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/collection_facets_scope.dart';
import 'package:compendium_app/src/search/collection_query.dart';

import '../support/facet_selection_table.dart';

void main() {
  group('persisted ids', () {
    test(
      'built-in ids are pinned: they are stored in settings, never rename',
      () {
        expect(CollectionFacetIds.builtIns, [
          'form',
          'formation',
          'progression',
          'status',
          'level',
          'mixed-level',
          'mixer',
          'min-rating',
          'call-status',
          'author',
          'tags',
          'source',
        ]);
      },
    );

    test('the selection table covers exactly the built-in ids', () {
      expect(
        builtInFacetSelections.keys.toSet(),
        CollectionFacetIds.builtIns.toSet(),
      );
    });

    test('a custom-field id is `cf:<defId>` and round-trips', () {
      expect(customFieldFacetId('abc'), 'cf:abc');
      expect(customFieldIdOfFacetId('cf:abc'), 'abc');
      expect(customFieldIdOfFacetId(customFieldFacetId('x:y')), 'x:y');
    });

    test('a built-in id is never read as a custom-field id', () {
      for (final id in CollectionFacetIds.builtIns) {
        expect(customFieldIdOfFacetId(id), isNull, reason: id);
      }
    });
  });

  group('decodeStored — nothing hidden unless a readable list says so', () {
    test('absent, non-list and empty values hide nothing', () {
      expect(CollectionFacetsScope.decodeStored(null), isEmpty);
      expect(CollectionFacetsScope.decodeStored('status'), isEmpty);
      expect(CollectionFacetsScope.decodeStored(7), isEmpty);
      expect(
        CollectionFacetsScope.decodeStored(<String, Object?>{'a': 1}),
        isEmpty,
      );
      expect(CollectionFacetsScope.decodeStored(<dynamic>[]), isEmpty);
    });

    test('non-string entries are dropped, strings are kept', () {
      expect(
        CollectionFacetsScope.decodeStored(<dynamic>[
          1,
          null,
          'tags',
          <dynamic>['nested'],
          'cf:abc',
        ]),
        {'tags', 'cf:abc'},
      );
    });

    test('an id this build does not know is kept, not discarded', () {
      // A newer build may hide a section this one has never heard of; writing
      // the set back must not lose it.
      expect(CollectionFacetsScope.decodeStored(<dynamic>['future-facet']), {
        'future-facet',
      });
    });

    test(
      'a new custom field is visible by default (deny-list, not allow-list)',
      () {
        // The hazard the deny-list exists for: saving the setting with only
        // `tags` hidden must not hide a field created afterwards.
        final hidden = CollectionFacetsScope.decodeStored(<dynamic>['tags']);
        expect(hidden.contains(customFieldFacetId('created-later')), isFalse);
      },
    );

    test('encode is sorted so the stored value ignores tick order', () {
      expect(CollectionFacetsScope.encode({'tags', 'author', 'cf:b', 'cf:a'}), [
        'author',
        'cf:a',
        'cf:b',
        'tags',
      ]);
    });
  });

  testWidgets('of() returns nothing hidden when no scope is mounted', (
    tester,
  ) async {
    late Set<String> seen;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          seen = CollectionFacetsScope.of(context);
          return const SizedBox();
        },
      ),
    );
    expect(seen, isEmpty);
  });

  testWidgets('of() tracks the notifier and notifierOf() throws without one', (
    tester,
  ) async {
    final notifier = ValueNotifier<Set<String>>(const {});
    addTearDown(notifier.dispose);
    var builds = 0;
    late Set<String> seen;
    await tester.pumpWidget(
      CollectionFacetsScope(
        notifier: notifier,
        child: Builder(
          builder: (context) {
            builds++;
            seen = CollectionFacetsScope.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen, isEmpty);

    notifier.value = {'status'};
    await tester.pump();
    expect(seen, {'status'});
    expect(builds, 2);

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          expect(
            () => CollectionFacetsScope.notifierOf(context),
            throwsFlutterError,
          );
          return const SizedBox();
        },
      ),
    );
  });

  group('FacetSelections.hasSelectionFor / clearFacets', () {
    for (final entry in builtInFacetSelections.entries) {
      test('built-in `${entry.key}`: held, cleared, others untouched', () {
        final facets = FacetSelections();
        // A neighbour that must survive: a different section from the target.
        final neighbourId = entry.key == CollectionFacetIds.tags
            ? CollectionFacetIds.author
            : CollectionFacetIds.tags;
        builtInFacetSelections[neighbourId]!.select(facets);
        expect(facets.hasSelectionFor(entry.key), isFalse);

        entry.value.select(facets);
        expect(facets.hasSelectionFor(entry.key), isTrue);
        expect(entry.value.held(facets), isTrue);

        expect(facets.clearFacets({entry.key}), isTrue);
        expect(facets.hasSelectionFor(entry.key), isFalse);
        expect(entry.value.held(facets), isFalse);
        expect(
          builtInFacetSelections[neighbourId]!.held(facets),
          isTrue,
          reason: 'clearing `${entry.key}` must not touch `$neighbourId`',
        );
      });
    }

    test(
      'custom fields clear by definition id across all four value kinds',
      () {
        final facets = FacetSelections()
          ..choiceValues['f1'] = {'red'}
          ..booleanValues['f2'] = true
          ..textValues['f3'] = const TextFacetState(
            op: CustomFieldOp.contains,
            value: 'x',
          )
          ..numberValues['f4'] = const NumberFacetState(
            op: CustomFieldOp.eq,
            lo: 2,
          )
          ..choiceValues['keep'] = {'blue'};

        for (final id in ['f1', 'f2', 'f3', 'f4']) {
          expect(
            facets.hasSelectionFor(customFieldFacetId(id)),
            isTrue,
            reason: id,
          );
        }
        expect(
          facets.clearFacets({
            for (final id in ['f1', 'f2', 'f3', 'f4']) customFieldFacetId(id),
          }),
          isTrue,
        );
        for (final id in ['f1', 'f2', 'f3', 'f4']) {
          expect(
            facets.hasSelectionFor(customFieldFacetId(id)),
            isFalse,
            reason: id,
          );
        }
        expect(facets.choiceValues, {
          'keep': {'blue'},
        });
      },
    );

    test('a custom-field id and a same-named built-in slug are different', () {
      final facets = FacetSelections()..tagIds.add('t1');
      expect(facets.hasSelectionFor(customFieldFacetId('tags')), isFalse);
      expect(facets.clearFacets({customFieldFacetId('tags')}), isFalse);
      expect(facets.tagIds, {'t1'});
    });

    test('unknown ids and empty sections are ignored and report no change', () {
      final facets = FacetSelections()..statuses.add(DanceStatus.draft);
      expect(facets.clearFacets({}), isFalse);
      expect(facets.clearFacets({'not-a-facet', 'cf:missing'}), isFalse);
      expect(facets.clearFacets({CollectionFacetIds.tags}), isFalse);
      expect(facets.statuses, {DanceStatus.draft});
    });

    test('an ineffective text/number state is not a selection', () {
      final facets = FacetSelections()
        ..textValues['t'] = const TextFacetState(
          op: CustomFieldOp.contains,
          value: '   ',
        )
        ..numberValues['n'] = const NumberFacetState(
          op: CustomFieldOp.between,
          lo: 1,
        );
      expect(facets.hasSelectionFor(customFieldFacetId('t')), isFalse);
      expect(facets.hasSelectionFor(customFieldFacetId('n')), isFalse);
      expect(facets.isEmpty, isTrue);
    });

    test('clearing every hidden id leaves activeCount and isEmpty in step', () {
      final facets = FacetSelections();
      for (final e in builtInFacetSelections.values) {
        e.select(facets);
      }
      expect(facets.activeCount, greaterThan(0));
      facets.clearFacets(CollectionFacetIds.builtIns.toSet());
      expect(facets.activeCount, 0);
      expect(facets.isEmpty, isTrue);
    });
  });
}
