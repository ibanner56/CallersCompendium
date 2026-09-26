import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/search/collection_query.dart';
import 'package:compendium_app/src/search/facet_labels.dart';
import 'package:compendium_app/src/widgets/facet_panel.dart';
import '../support/l10n_harness.dart';
import '../support/screen_size.dart';

Future<void> _pump(
  WidgetTester tester,
  FacetSelections facets, {
  List<Progression> progressions = const [],
  List<DanceLevel> levels = const [],
  List<FormationShape> formations = const [],
  List<CustomFieldDef> choiceFields = const [],
  List<PublishedSource> citedSources = const [],
  List<Choreographer> authors = const [],
  List<String> tunes = const [],
  bool hasMixedLevel = false,
  bool hasMixer = false,
  bool hasRating = false,
  bool hasCallingHistory = false,
  // Only set when a test needs to exercise ResponsiveAutocomplete's narrow
  // layout; existing (unset) tests keep relying on the default test window
  // (800x600), which is already comfortably above the compact width/height
  // breakpoints (600/480), so the author facet's wide inline overlay
  // behaves exactly as it did before the ResponsiveAutocomplete migration.
  Size? screenSize,
  required VoidCallback onChanged,
}) async {
  if (screenSize != null) {
    await setScreenSize(tester, screenSize);
  }
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: FacetPanel(
              facets: facets,
              forms: const [],
              formations: formations,
              progressions: progressions,
              statuses: const [],
              levels: levels,
              hasMixedLevel: hasMixedLevel,
              hasMixer: hasMixer,
              hasRating: hasRating,
              hasCallingHistory: hasCallingHistory,
              authors: authors,
              tags: const [],
              citedSources: citedSources,
              tunes: tunes,
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
  testWidgets('reverse progression formation is data-backed and selectable', (
    tester,
  ) async {
    final facets = FacetSelections();
    await _pump(
      tester,
      facets,
      formations: const [FormationShape.reverseProgressionImproper],
      onChanged: () {},
    );

    expect(find.text('Reverse progression improper'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('formation-reverseProgressionImproper')),
    );
    await tester.pump();

    expect(
      facets.formations,
      contains(FormationShape.reverseProgressionImproper),
    );
  });

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

    expect(facets.levels, contains(DifficultyLevel.intermediateId));
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

  testWidgets('calling-history chips toggle called status selections', (
    tester,
  ) async {
    final facets = FacetSelections();
    var changes = 0;
    await _pump(
      tester,
      facets,
      hasCallingHistory: true,
      onChanged: () => changes++,
    );

    expect(find.text('Calling history'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('call-status-called')));
    await tester.pump();
    expect(facets.callStatuses, {true});

    await tester.tap(find.byKey(const ValueKey('call-status-not-called')));
    await tester.pump();
    expect(facets.callStatuses, {true, false});
    expect(changes, 2);

    await tester.tap(find.byKey(const ValueKey('call-status-called')));
    await tester.pump();
    expect(facets.callStatuses, {false});
  });

  testWidgets('calling-history section is hidden without qualifying calls', (
    tester,
  ) async {
    await _pump(tester, FacetSelections(), onChanged: () {});
    expect(find.text('Calling history'), findsNothing);
    expect(find.byKey(const ValueKey('call-status-called')), findsNothing);
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

  testWidgets('a collapsed section stays collapsed when a filter is applied '
      'elsewhere (#375)', (tester) async {
    // Regression: the Column's direct children are keyed, so prepending the
    // Clear-filters row on the first selection must not remount the keyed
    // ExpansionTiles and re-expand a section the user collapsed.
    final facets = FacetSelections();
    await _pump(
      tester,
      facets,
      progressions: Progression.values,
      levels: DanceLevel.values,
      onChanged: () {},
    );

    // Both sections start expanded, so their chips are in the tree.
    expect(find.byKey(const ValueKey('progression-single')), findsOneWidget);

    // Collapse the Progression section by tapping its header.
    await tester.tap(find.text('Progression'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('progression-single')), findsNothing);

    // Apply the first filter in a different section — this flips
    // `facets.isEmpty` and prepends the Clear-filters row.
    await tester.tap(find.byKey(const ValueKey('level-beginner')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('clear-filters')), findsOneWidget);

    // The collapsed Progression section must remain collapsed.
    expect(find.byKey(const ValueKey('progression-single')), findsNothing);
  });

  group('author multi-select (#341)', () {
    final authors = [
      Choreographer(id: 'c1', name: 'Folk Process'),
      Choreographer(id: 'c2', name: 'Grace Hopper'),
      Choreographer(id: 'c3', name: 'Gene Hubert'),
    ];

    testWidgets('the section is hidden when there are no authors', (
      tester,
    ) async {
      await _pump(tester, FacetSelections(), onChanged: () {});
      expect(find.text('Author'), findsNothing);
      expect(find.byKey(const ValueKey('author-facet-search')), findsNothing);
    });

    testWidgets('renders the search field and no chips before any selection', (
      tester,
    ) async {
      await _pump(
        tester,
        FacetSelections(),
        authors: authors,
        onChanged: () {},
      );
      expect(find.text('Author'), findsOneWidget);
      expect(find.byKey(const ValueKey('author-facet-search')), findsOneWidget);
      // No per-author chips are pre-rendered (the old flat list is gone).
      expect(find.byKey(const ValueKey('author-facet-chip-c1')), findsNothing);
    });

    testWidgets('typing filters the options to name substring matches', (
      tester,
    ) async {
      await _pump(
        tester,
        FacetSelections(),
        authors: authors,
        onChanged: () {},
      );

      await tester.enterText(
        find.byKey(const ValueKey('author-facet-search')),
        'grace',
      );
      await tester.pumpAndSettle();

      // Only Grace Hopper matches "grace" (case-insensitive).
      expect(
        find.byKey(const ValueKey('author-facet-option-c2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('author-facet-option-c1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('author-facet-option-c3')),
        findsNothing,
      );
    });

    testWidgets('selecting an author adds it to authorIds and shows a chip', (
      tester,
    ) async {
      final facets = FacetSelections();
      var changes = 0;
      await _pump(tester, facets, authors: authors, onChanged: () => changes++);

      await tester.enterText(
        find.byKey(const ValueKey('author-facet-search')),
        'folk',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('author-facet-option-c1')));
      await tester.pumpAndSettle();

      expect(facets.authorIds, {'c1'});
      expect(changes, 1);
      expect(
        find.byKey(const ValueKey('author-facet-chip-c1')),
        findsOneWidget,
      );
    });

    testWidgets('selecting two authors OR-s them within the facet', (
      tester,
    ) async {
      final facets = FacetSelections();
      await _pump(tester, facets, authors: authors, onChanged: () {});

      await tester.enterText(
        find.byKey(const ValueKey('author-facet-search')),
        'folk',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('author-facet-option-c1')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('author-facet-search')),
        'grace',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('author-facet-option-c2')));
      await tester.pumpAndSettle();

      expect(facets.authorIds, {'c1', 'c2'});
    });

    testWidgets('an already-selected author is excluded from the options', (
      tester,
    ) async {
      final facets = FacetSelections()..authorIds.add('c1');
      await _pump(tester, facets, authors: authors, onChanged: () {});

      // "a" matches Ada and Grace, but Ada (c1) is already selected.
      await tester.enterText(
        find.byKey(const ValueKey('author-facet-search')),
        'a',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('author-facet-option-c1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('author-facet-option-c2')),
        findsOneWidget,
      );
    });

    testWidgets('removing the last chip leaves authorIds empty (no dangling '
        'filter)', (tester) async {
      final facets = FacetSelections()..authorIds.add('c1');
      var changes = 0;
      await _pump(tester, facets, authors: authors, onChanged: () => changes++);

      expect(
        find.byKey(const ValueKey('author-facet-chip-c1')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('author-facet-chip-c1')),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();

      expect(facets.authorIds, isEmpty);
      expect(changes, 1);
      expect(find.byKey(const ValueKey('author-facet-chip-c1')), findsNothing);

      // An empty author facet contributes no filter branch: with nothing else
      // selected the query compiles to the match-all AndFilter([]).
      final filter = buildCollectionFilter(
        ftsText: '',
        facets: facets,
        defs: const [],
      );
      expect(filter, isA<AndFilter>());
      expect((filter as AndFilter).children, isEmpty);
    });

    testWidgets('two selected authors compile to the same OR-group of '
        'AuthorFilters (semantics unchanged)', (tester) async {
      final facets = FacetSelections();
      await _pump(tester, facets, authors: authors, onChanged: () {});

      await tester.enterText(
        find.byKey(const ValueKey('author-facet-search')),
        'folk',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('author-facet-option-c1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('author-facet-search')),
        'grace',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('author-facet-option-c2')));
      await tester.pumpAndSettle();

      final filter = buildCollectionFilter(
        ftsText: '',
        facets: facets,
        defs: const [],
      );
      expect(filter, isA<OrFilter>());
      final leaves = (filter as OrFilter).children;
      expect(leaves.every((f) => f is AuthorFilter), isTrue);
      expect(leaves.map((f) => (f as AuthorFilter).choreographerId).toSet(), {
        'c1',
        'c2',
      });
    });

    testWidgets(
      'narrow layout: picking an author from the keyboard-safe sheet adds '
      'it and closes the sheet, with the option fully visible above a '
      'simulated keyboard inset (#716)',
      (tester) async {
        final facets = FacetSelections();
        var changes = 0;
        await _pump(
          tester,
          facets,
          authors: authors,
          screenSize: const Size(360, 720),
          onChanged: () => changes++,
        );

        await tester.tap(
          find.byKey(const ValueKey('author-facet-search')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);

        // Simulate a software keyboard inset, as issue #716 describes.
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('author-facet-search')),
          'folk',
        );
        await tester.pumpAndSettle();

        final option = find.byKey(const ValueKey('author-facet-option-c1'));
        expect(option, findsOneWidget);
        final optionRect = tester.getRect(option);
        final screenHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        expect(optionRect.bottom, lessThanOrEqualTo(screenHeight - 300));

        await tester.tap(option);
        await tester.pumpAndSettle();

        expect(facets.authorIds, {'c1'});
        expect(changes, 1);
        // Picking always closes the sheet (owner's Q1 decision, uniform
        // across all seven call sites, including multi-select facets like
        // this one — tap the search field again to add another author).
        expect(find.byType(BottomSheet), findsNothing);
        expect(
          find.byKey(const ValueKey('author-facet-chip-c1')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'narrow layout: the search field re-opens with an empty query for '
      'the next author (#716)',
      (tester) async {
        final facets = FacetSelections();
        await _pump(
          tester,
          facets,
          authors: authors,
          screenSize: const Size(360, 720),
          onChanged: () {},
        );

        await tester.tap(
          find.byKey(const ValueKey('author-facet-search')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('author-facet-search')),
          'folk',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('author-facet-option-c1')));
        await tester.pumpAndSettle();

        // Tap again to add a second author: the sheet must re-open with an
        // empty query (the cleared launcher's own text), not "folk" left
        // over from the first pick.
        await tester.tap(
          find.byKey(const ValueKey('author-facet-search')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        final sheetField = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byKey(const ValueKey('author-facet-search')),
        );
        expect(tester.widget<TextField>(sheetField).controller!.text, '');
        // The already-selected c1 is excluded, so an empty query still
        // shows no options until the caller types again — same contract as
        // the wide layout.
        expect(
          find.byKey(const ValueKey('author-facet-option-c2')),
          findsNothing,
        );

        await tester.enterText(sheetField, 'grace');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('author-facet-option-c2')));
        await tester.pumpAndSettle();

        expect(facets.authorIds, {'c1', 'c2'});
      },
    );
  });

  group('mixer facet (issue #732)', () {
    testWidgets('mixer facet hidden when hasMixer is false', (tester) async {
      final facets = FacetSelections();
      await _pump(tester, facets, hasMixer: false, onChanged: () {});
      expect(find.byKey(const ValueKey('mixer-yes')), findsNothing);
    });

    testWidgets('mixer facet shown when hasMixer is true', (tester) async {
      final facets = FacetSelections();
      await _pump(tester, facets, hasMixer: true, onChanged: () {});
      expect(find.byKey(const ValueKey('mixer-yes')), findsOneWidget);
    });

    testWidgets('tapping mixer chip sets mixer to true', (tester) async {
      final facets = FacetSelections();
      await _pump(tester, facets, hasMixer: true, onChanged: () {});
      await tester.tap(find.byKey(const ValueKey('mixer-yes')));
      await tester.pumpAndSettle();
      expect(facets.mixer, isTrue);
    });

    testWidgets('tapping active mixer chip clears it (tri-state null)', (
      tester,
    ) async {
      final facets = FacetSelections()..mixer = true;
      await _pump(tester, facets, hasMixer: true, onChanged: () {});
      await tester.tap(find.byKey(const ValueKey('mixer-yes')));
      await tester.pumpAndSettle();
      expect(facets.mixer, isNull);
    });
  });

  group('Tunes facet (#1420)', () {
    const tunes = ['Dmaj', 'Dmaj / Bmin', 'Gmaj 6/8'];
    final search = find.byKey(const ValueKey('tunes-facet-search'));
    final typedOption = find.byKey(const ValueKey('tunes-facet-option-typed'));

    Finder chip(String tune) => find.byKey(ValueKey('tunes-facet-chip-$tune'));

    testWidgets('is hidden when no dance has tunes and none is selected', (
      tester,
    ) async {
      await _pump(tester, FacetSelections(), onChanged: () {});
      expect(find.byKey(const ValueKey('facet-section-tunes')), findsNothing);
    });

    testWidgets('an entered value keeps the section visible after the '
        'vocabulary empties, so it can still be removed', (tester) async {
      final facets = FacetSelections()..addTune('Dmaj');
      await _pump(tester, facets, onChanged: () {});
      expect(find.byKey(const ValueKey('facet-section-tunes')), findsOneWidget);
      expect(chip('Dmaj'), findsOneWidget);
    });

    testWidgets('picking a suggestion adds a chip and notifies once', (
      tester,
    ) async {
      final facets = FacetSelections();
      var changes = 0;
      await _pump(tester, facets, tunes: tunes, onChanged: () => changes++);

      await tester.enterText(search, 'bmin');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('tunes-facet-option-Dmaj / Bmin')),
      );
      await tester.pumpAndSettle();

      expect(facets.tunes, ['Dmaj / Bmin']);
      expect(changes, 1);
      expect(chip('Dmaj / Bmin'), findsOneWidget);
      // The field is reset for the next value.
      expect(tester.widget<TextField>(search).controller!.text, '');
    });

    testWidgets('Enter commits the typed text, not the first suggestion', (
      tester,
    ) async {
      final facets = FacetSelections();
      await _pump(tester, facets, tunes: tunes, onChanged: () {});

      // "Dmaj / Bmin" and "Dmaj" both contain "dma"; the user typed "dma" and
      // means exactly that substring.
      await tester.enterText(search, 'dma');
      await tester.pumpAndSettle();
      expect(typedOption, findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(facets.tunes, ['dma']);
    });

    testWidgets('free text with no suggestion at all still commits', (
      tester,
    ) async {
      final facets = FacetSelections();
      await _pump(tester, facets, tunes: tunes, onChanged: () {});

      await tester.enterText(search, 'Emin');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(facets.tunes, ['Emin']);
      expect(chip('Emin'), findsOneWidget);
    });

    testWidgets('no typed-text row is offered when a suggestion says the '
        'same thing', (tester) async {
      await _pump(tester, FacetSelections(), tunes: tunes, onChanged: () {});
      await tester.enterText(search, 'DMAJ');
      await tester.pumpAndSettle();
      expect(typedOption, findsNothing);
      expect(
        find.byKey(const ValueKey('tunes-facet-option-Dmaj')),
        findsOneWidget,
      );
    });

    testWidgets('a value already entered is not offered again, and a blank '
        'commit changes nothing', (tester) async {
      final facets = FacetSelections()..addTune('Dmaj');
      var changes = 0;
      await _pump(tester, facets, tunes: tunes, onChanged: () => changes++);

      await tester.enterText(search, 'dmaj');
      await tester.pumpAndSettle();
      expect(typedOption, findsNothing);
      expect(
        find.byKey(const ValueKey('tunes-facet-option-Dmaj')),
        findsNothing,
      );

      await tester.enterText(search, '   ');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(facets.tunes, ['Dmaj']);
      expect(changes, 0);
    });

    testWidgets('deleting a chip removes the value and notifies', (
      tester,
    ) async {
      final facets = FacetSelections()
        ..addTune('Dmaj')
        ..addTune('6/8');
      var changes = 0;
      await _pump(tester, facets, tunes: tunes, onChanged: () => changes++);

      await tester.tap(
        find.descendant(of: chip('Dmaj'), matching: find.byIcon(Icons.close)),
      );
      await tester.pumpAndSettle();

      expect(facets.tunes, ['6/8']);
      expect(changes, 1);
      expect(chip('Dmaj'), findsNothing);
    });

    testWidgets('entered values compile to AND-ed TunesFilters and drive the '
        'section badge', (tester) async {
      final facets = FacetSelections();
      await _pump(tester, facets, tunes: tunes, onChanged: () {});
      for (final text in ['Dmaj', '6/8']) {
        await tester.enterText(search, text);
        await tester.pumpAndSettle();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }

      final filter = buildCollectionFilter(
        ftsText: '',
        facets: facets,
        defs: const [],
      );
      expect(filter, isA<AndFilter>());
      expect(
        [
          for (final f in (filter as AndFilter).children)
            (f as TunesFilter).query,
        ],
        ['Dmaj', '6/8'],
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('facet-section-tunes')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('narrow layout: picking from the sheet adds the chip and '
        'closes the sheet', (tester) async {
      final facets = FacetSelections();
      await _pump(
        tester,
        facets,
        tunes: tunes,
        screenSize: const Size(360, 720),
        onChanged: () {},
      );

      await tester.tap(search, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.enterText(search, 'gmaj');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('tunes-facet-option-Gmaj 6/8')),
      );
      await tester.pumpAndSettle();

      expect(facets.tunes, ['Gmaj 6/8']);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });
}
