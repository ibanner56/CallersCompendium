import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/collection_facets_scope.dart';
import 'package:compendium_app/src/search/collection_query.dart';
import 'package:compendium_app/src/widgets/facet_panel.dart';
import '../support/facet_selection_table.dart';
import '../support/l10n_harness.dart';

// The four searchable custom-field kinds, one of each, so every section the
// panel can render is present at once.
final _choice = CustomFieldDef(
  id: 'fc',
  key: 'fc',
  label: 'Region',
  type: CustomFieldType.choice,
  choices: const ['north', 'south'],
);
final _bool = CustomFieldDef(
  id: 'fb',
  key: 'fb',
  label: 'Has walkthrough',
  type: CustomFieldType.boolean,
);
final _text = CustomFieldDef(
  id: 'ft',
  key: 'ft',
  label: 'Notes',
  type: CustomFieldType.text,
);
final _number = CustomFieldDef(
  id: 'fn',
  key: 'fn',
  label: 'Difficulty',
  type: CustomFieldType.number,
);

/// The widget key of each section, by the id the user hides it under.
final _rowKeys = <String, Key>{
  for (final id in CollectionFacetIds.builtIns) id: ValueKey('facet-row-$id'),
  customFieldFacetId('fc'): const ValueKey('facet-row-cf-choice-fc'),
  customFieldFacetId('fb'): const ValueKey('facet-row-cf-bool-fb'),
  customFieldFacetId('ft'): const ValueKey('cf-text-ft'),
  customFieldFacetId('fn'): const ValueKey('cf-num-fn'),
};

/// Pumps a [FacetPanel] with data for *every* section, under a
/// [CollectionFacetsScope] holding [hidden] (or none when [scoped] is false).
Future<ValueNotifier<Set<String>>> _pump(
  WidgetTester tester,
  FacetSelections facets, {
  Set<String> hidden = const {},
  bool scoped = true,
  bool everySectionHasData = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Set<String>>(hidden);
  addTearDown(notifier.dispose);

  final has = everySectionHasData;
  Widget panel() => StatefulBuilder(
    builder: (context, setState) => FacetPanel(
      facets: facets,
      forms: has ? DanceForm.values : const [],
      formations: has ? const [FormationShape.becketCw] : const [],
      progressions: has ? const [Progression.single] : const [],
      statuses: has ? const [DanceStatus.draft] : const [],
      levels: has ? DanceLevel.values : const [],
      hasMixedLevel: has,
      hasMixer: has,
      hasRating: has,
      hasCallingHistory: has,
      authors: has ? [Choreographer(id: 'a1', name: 'Folk Process')] : const [],
      tags: has ? [Tag(id: 't1', name: 'Beginner')] : const [],
      citedSources: has
          ? [PublishedSource(id: 's1', title: 'Zesty Contras')]
          : const [],
      choiceFields: has ? [_choice] : const [],
      booleanFields: has ? [_bool] : const [],
      textFields: has ? [_text] : const [],
      numberFields: has ? [_number] : const [],
      onChanged: () => setState(() {}),
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: scoped
              ? CollectionFacetsScope(notifier: notifier, child: panel())
              : panel(),
        ),
      ),
    ),
  );
  await tester.pump();
  return notifier;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(FacetPanel)));

void main() {
  test('the row-key table covers every hideable section', () {
    // A section added to the panel and to CollectionFacetIds must be added here
    // too, or the per-section tests below silently skip it.
    expect(_rowKeys.keys.toSet(), {
      ...CollectionFacetIds.builtIns,
      for (final id in ['fc', 'fb', 'ft', 'fn']) customFieldFacetId(id),
    });
  });

  group('nothing hidden', () {
    testWidgets('an unset preference shows every section', (tester) async {
      await _pump(tester, FacetSelections());
      for (final entry in _rowKeys.entries) {
        expect(find.byKey(entry.value), findsWidgets, reason: entry.key);
      }
    });

    testWidgets('a panel with no scope mounted shows every section', (
      tester,
    ) async {
      // The Collection/picker tests and any embedder that never installs the
      // scope must behave exactly as before this preference existed.
      await _pump(tester, FacetSelections(), scoped: false);
      for (final entry in _rowKeys.entries) {
        expect(find.byKey(entry.value), findsWidgets, reason: entry.key);
      }
    });
  });

  group('hiding one section', () {
    for (final id in _rowKeys.keys) {
      testWidgets('`$id` disappears and every other section stays', (
        tester,
      ) async {
        await _pump(tester, FacetSelections(), hidden: {id});
        expect(find.byKey(_rowKeys[id]!), findsNothing);
        for (final other in _rowKeys.entries.where((e) => e.key != id)) {
          expect(
            find.byKey(other.value),
            findsWidgets,
            reason: 'hiding `$id` must not hide `${other.key}`',
          );
        }
      });
    }

    testWidgets('an unknown id and a stale custom-field id hide nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        FacetSelections(),
        hidden: {'future-facet', customFieldFacetId('deleted-field')},
      );
      for (final entry in _rowKeys.entries) {
        expect(find.byKey(entry.value), findsWidgets, reason: entry.key);
      }
    });

    testWidgets('same-label custom fields are hidden by id, not by label', (
      tester,
    ) async {
      final twin = CustomFieldDef(
        id: 'twin',
        key: 'twin',
        label: 'Region', // same label as _choice
        type: CustomFieldType.choice,
        choices: const ['east'],
      );
      final facets = FacetSelections();
      final hidden = ValueNotifier<Set<String>>({customFieldFacetId('fc')});
      addTearDown(hidden.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: CollectionFacetsScope(
              notifier: hidden,
              child: FacetPanel(
                facets: facets,
                forms: const [],
                formations: const [],
                progressions: const [],
                statuses: const [],
                levels: const [],
                hasMixedLevel: false,
                hasMixer: false,
                hasRating: false,
                authors: const [],
                tags: const [],
                citedSources: const [],
                choiceFields: [_choice, twin],
                booleanFields: const [],
                textFields: const [],
                numberFields: const [],
                onChanged: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('facet-row-cf-choice-fc')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('facet-row-cf-choice-twin')),
        findsWidgets,
      );
    });
  });

  group('a hidden section that holds a selection stays visible', () {
    testWidgets('every built-in facet', (tester) async {
      // The tag chip on the dance-detail page selects a tag without going
      // through this panel; a filter narrowing the list must have a control.
      for (final id in CollectionFacetIds.builtIns) {
        final facets = FacetSelections();
        builtInFacetSelections[id]!.select(facets);
        await _pump(
          tester,
          facets,
          hidden: CollectionFacetIds.builtIns.toSet(),
        );
        // Only the selected section survives a hide-everything preference.
        expect(find.byKey(_rowKeys[id]!), findsWidgets, reason: id);
        for (final other in CollectionFacetIds.builtIns.where((o) => o != id)) {
          expect(
            find.byKey(_rowKeys[other]!),
            findsNothing,
            reason: '$id/$other',
          );
        }
      }
    });

    testWidgets('custom fields of every value kind', (tester) async {
      final facets = FacetSelections()
        ..choiceValues['fc'] = {'north'}
        ..booleanValues['fb'] = true
        ..textValues['ft'] = const TextFacetState(
          op: CustomFieldOp.contains,
          value: 'walk',
        )
        ..numberValues['fn'] = const NumberFacetState(
          op: CustomFieldOp.eq,
          lo: 3,
        );
      await _pump(
        tester,
        facets,
        hidden: {
          for (final id in ['fc', 'fb', 'ft', 'fn']) customFieldFacetId(id),
        },
      );
      for (final id in ['fc', 'fb', 'ft', 'fn']) {
        expect(
          find.byKey(_rowKeys[customFieldFacetId(id)]!),
          findsWidgets,
          reason: id,
        );
      }
    });

    testWidgets('and goes away once its last selection is cleared', (
      tester,
    ) async {
      final facets = FacetSelections()..statuses.add(DanceStatus.draft);
      await _pump(tester, facets, hidden: {CollectionFacetIds.status});
      expect(find.byKey(_rowKeys[CollectionFacetIds.status]!), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('status-draft')));
      await tester.pump();
      expect(facets.statuses, isEmpty);
      expect(find.byKey(_rowKeys[CollectionFacetIds.status]!), findsNothing);
    });
  });

  group('live update', () {
    testWidgets('changing the notifier hides and re-shows a section', (
      tester,
    ) async {
      final hidden = await _pump(tester, FacetSelections());
      final status = find.byKey(_rowKeys[CollectionFacetIds.status]!);
      expect(status, findsWidgets);

      hidden.value = {CollectionFacetIds.status};
      await tester.pump();
      expect(status, findsNothing);

      hidden.value = const {};
      await tester.pump();
      expect(status, findsWidgets);
    });
  });

  group('empty states', () {
    testWidgets('every section hidden says so, not "no filters yet"', (
      tester,
    ) async {
      await _pump(
        tester,
        FacetSelections(),
        hidden: {
          ...CollectionFacetIds.builtIns,
          for (final id in ['fc', 'fb', 'ft', 'fn']) customFieldFacetId(id),
        },
      );
      final l10n = _l10n(tester);
      expect(find.text(l10n.collectionFacetAllHidden), findsOneWidget);
      expect(find.text(l10n.collectionFacetNone), findsNothing);
    });

    testWidgets('a collection with nothing to filter keeps the old message', (
      tester,
    ) async {
      // Nothing is *suppressed* here — there was nothing to show — so hiding a
      // section the collection has no data for must not change the message.
      await _pump(
        tester,
        FacetSelections(),
        hidden: CollectionFacetIds.builtIns.toSet(),
        everySectionHasData: false,
      );
      final l10n = _l10n(tester);
      expect(find.text(l10n.collectionFacetNone), findsOneWidget);
      expect(find.text(l10n.collectionFacetAllHidden), findsNothing);
    });

    testWidgets('some sections still visible shows neither message', (
      tester,
    ) async {
      await _pump(tester, FacetSelections(), hidden: {CollectionFacetIds.tags});
      final l10n = _l10n(tester);
      expect(find.text(l10n.collectionFacetAllHidden), findsNothing);
      expect(find.text(l10n.collectionFacetNone), findsNothing);
    });
  });
}
