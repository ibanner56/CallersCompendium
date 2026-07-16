import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/search/collection_query.dart';
import 'package:compendium_app/src/search/facet_labels.dart';
import 'package:compendium_app/src/widgets/facet_panel.dart';

Future<void> _pump(
  WidgetTester tester,
  FacetSelections facets, {
  List<Progression> progressions = const [],
  List<DanceLevel> levels = const [],
  List<CustomFieldDef> choiceFields = const [],
  List<PublishedSource> citedSources = const [],
  bool hasMixedLevel = false,
  bool hasRating = false,
  required VoidCallback onChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: FacetPanel(
              facets: facets,
              forms: const [],
              formations: const [],
              progressions: progressions,
              statuses: const [],
              levels: levels,
              hasMixedLevel: hasMixedLevel,
              hasRating: hasRating,
              authors: const [],
              tags: const [],
              citedSources: citedSources,
              choiceFields: choiceFields,
              booleanFields: const [],
              textFields: const [],
              numberFields: const [],
              // Rebuild the panel so chip `selected` state reflects the mutated
              // selections, mirroring the real screen's setState on change.
              onChanged: () {
                onChanged();
                setState(() {});
              },
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('progression chips use the centralized progressionIcon', (
    tester,
  ) async {
    // 6.5 parity: the Progression facet value chips must use the app-wide
    // `progressionIcon` (matching the Formation facet), not the legacy
    // `Icons.trending_flat`.
    final facets = FacetSelections();
    var changes = 0;
    await _pump(
      tester,
      facets,
      progressions: Progression.values,
      onChanged: () => changes++,
    );

    expect(find.text('Progression'), findsOneWidget);
    expect(find.byIcon(progressionIcon), findsWidgets);
    expect(find.byIcon(Icons.trending_flat), findsNothing);

    await tester.tap(find.byKey(const ValueKey('progression-single')));
    await tester.pump();
    expect(facets.progressions, contains(Progression.single));
    expect(changes, 1);
  });

  testWidgets('level chips toggle the selection and notify', (tester) async {
    final facets = FacetSelections();
    var changes = 0;
    await _pump(
      tester,
      facets,
      levels: DanceLevel.values,
      onChanged: () => changes++,
    );

    expect(find.text('Level'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('level-intermediate')));
    await tester.pump();

    expect(facets.levels, contains(DanceLevel.intermediate));
    expect(changes, 1);

    // Toggling again removes it.
    await tester.tap(find.byKey(const ValueKey('level-intermediate')));
    await tester.pump();
    expect(facets.levels, isEmpty);
    expect(changes, 2);
  });

  testWidgets('mixed-level chip sets and clears the flag', (tester) async {
    final facets = FacetSelections();
    var changes = 0;
    await _pump(
      tester,
      facets,
      hasMixedLevel: true,
      onChanged: () => changes++,
    );

    await tester.tap(find.byKey(const ValueKey('mixed-level-yes')));
    await tester.pump();
    expect(facets.mixedLevel, isTrue);
    expect(changes, 1);

    await tester.tap(find.byKey(const ValueKey('mixed-level-yes')));
    await tester.pump();
    expect(facets.mixedLevel, isNull);
    expect(changes, 2);
  });

  testWidgets('level section is hidden when no levels are present', (
    tester,
  ) async {
    await _pump(tester, FacetSelections(), onChanged: () {});
    expect(find.text('Level'), findsNothing);
    expect(find.byKey(const ValueKey('mixed-level-yes')), findsNothing);
  });

  testWidgets('minimum-rating chip sets and clears the floor', (tester) async {
    final facets = FacetSelections();
    var changes = 0;
    await _pump(tester, facets, hasRating: true, onChanged: () => changes++);

    expect(find.text('Minimum rating'), findsOneWidget);

    // Selecting ≥4 sets the floor.
    await tester.tap(find.byKey(const ValueKey('min-rating-4')));
    await tester.pump();
    expect(facets.minRating, 4);
    expect(changes, 1);

    // Selecting ≥2 switches the floor (single-valued).
    await tester.tap(find.byKey(const ValueKey('min-rating-2')));
    await tester.pump();
    expect(facets.minRating, 2);
    expect(changes, 2);

    // Tapping the current selection clears it (removes the RatingFilter).
    await tester.tap(find.byKey(const ValueKey('min-rating-2')));
    await tester.pump();
    expect(facets.minRating, isNull);
    expect(changes, 3);
  });

  testWidgets('minimum-rating floor compiles to RatingFilter(4)', (
    tester,
  ) async {
    final facets = FacetSelections();
    await _pump(tester, facets, hasRating: true, onChanged: () {});

    await tester.tap(find.byKey(const ValueKey('min-rating-4')));
    await tester.pump();

    final filter = buildCollectionFilter(
      ftsText: '',
      facets: facets,
      defs: const [],
    );
    expect(filter, isA<RatingFilter>());
    expect((filter as RatingFilter).minimum, 4);
  });

  testWidgets('minimum-rating section is hidden when no dance is rated', (
    tester,
  ) async {
    await _pump(tester, FacetSelections(), onChanged: () {});
    expect(find.text('Minimum rating'), findsNothing);
    expect(find.byKey(const ValueKey('min-rating-4')), findsNothing);
  });

  testWidgets('a section shows an active-count badge when selections exist', (
    tester,
  ) async {
    final facets = FacetSelections();
    await _pump(tester, facets, levels: DanceLevel.values, onChanged: () {});

    // No badge before any selection.
    expect(find.byType(Badge), findsNothing);

    await tester.tap(find.byKey(const ValueKey('level-beginner')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('level-advanced')));
    await tester.pump();

    // The Level section now surfaces a "2" count badge.
    final badge = find.byType(Badge);
    expect(badge, findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('the Clear filters bar appears only when a facet is active and '
      'clears every selection', (tester) async {
    final facets = FacetSelections();
    var changes = 0;
    await _pump(
      tester,
      facets,
      levels: DanceLevel.values,
      onChanged: () => changes++,
    );

    // Hidden while nothing is selected.
    expect(find.byKey(const ValueKey('clear-filters')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('level-intermediate')));
    await tester.pump();
    expect(find.byKey(const ValueKey('clear-filters')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clear-filters')));
    await tester.pump();

    expect(facets.isEmpty, isTrue);
    expect(facets.levels, isEmpty);
    // Selecting (1) + clearing (1) both notify the parent.
    expect(changes, 2);
    expect(find.byKey(const ValueKey('clear-filters')), findsNothing);
  });

  testWidgets('two custom-field sections with the same label do not collide', (
    tester,
  ) async {
    // Custom-field labels are user-authored and not unique; sections must be
    // keyed by the field id so a shared label can't trigger the duplicate-key
    // assertion.
    await _pump(
      tester,
      FacetSelections(),
      choiceFields: [
        CustomFieldDef(
          id: 'a',
          key: 'a',
          label: 'Region',
          type: CustomFieldType.choice,
          choices: const ['north', 'south'],
        ),
        CustomFieldDef(
          id: 'b',
          key: 'b',
          label: 'Region',
          type: CustomFieldType.choice,
          choices: const ['east', 'west'],
        ),
      ],
      onChanged: () {},
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Region'), findsNWidgets(2));
    // Both fields' chips are reachable (distinct keys, not colliding sections).
    expect(find.byKey(const ValueKey('cf-a-north')), findsOneWidget);
    expect(find.byKey(const ValueKey('cf-b-east')), findsOneWidget);
  });

  testWidgets('source section is hidden when nothing is cited', (tester) async {
    await _pump(tester, FacetSelections(), onChanged: () {});
    expect(find.text('Source'), findsNothing);
  });

  testWidgets('source chips toggle the selected source ids', (tester) async {
    final facets = FacetSelections();
    var changes = 0;
    await _pump(
      tester,
      facets,
      citedSources: [
        PublishedSource(id: 's1', title: 'Zesty Contras'),
        PublishedSource(id: 's2', title: 'Give-and-Take'),
      ],
      onChanged: () => changes++,
    );

    expect(find.text('Source'), findsOneWidget);
    // Chip label is the source title; the emitted/selected value is its id.
    expect(find.text('Zesty Contras'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('source-s1')));
    await tester.pump();
    expect(facets.sourceIds, contains('s1'));
    expect(changes, 1);

    // Multi-select: a second source OR-s in.
    await tester.tap(find.byKey(const ValueKey('source-s2')));
    await tester.pump();
    expect(facets.sourceIds, {'s1', 's2'});

    // Toggling clears just that id.
    await tester.tap(find.byKey(const ValueKey('source-s1')));
    await tester.pump();
    expect(facets.sourceIds, {'s2'});
  });
}
