import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/search/collection_query.dart';
import 'package:compendium_app/src/widgets/facet_panel.dart';

Future<void> _pump(
  WidgetTester tester,
  FacetSelections facets, {
  List<DanceLevel> levels = const [],
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
              progressions: const [],
              statuses: const [],
              levels: levels,
              hasMixedLevel: hasMixedLevel,
              hasRating: hasRating,
              authors: const [],
              tags: const [],
              choiceFields: const [],
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
}
