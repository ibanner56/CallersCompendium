import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations_en.dart';
import 'package:compendium_app/src/search/called_venue_choices.dart';
import 'package:compendium_app/src/search/collection_query.dart';
import 'package:compendium_app/src/search/facet_labels.dart';
import 'package:compendium_app/src/widgets/facet_panel.dart';

import '../support/l10n_harness.dart';
import '../support/screen_size.dart';
import '../support/test_repositories.dart';

Future<void> _pump(
  WidgetTester tester,
  FacetSelections facets, {
  List<Progression> progressions = const [],
  List<DanceLevel> levels = const [],
  List<FormationShape> formations = const [],
  List<CustomFieldDef> choiceFields = const [],
  List<CustomFieldDef> textFields = const [],
  List<PublishedSource> citedSources = const [],
  List<Choreographer> authors = const [],
  List<String> tunes = const [],
  List<Tag> tags = const [],
  bool hasMixedLevel = false,
  bool hasMixer = false,
  bool hasRating = false,
  bool hasCallingHistory = false,
  VenueChoiceSource? venueChoices,
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
              venueChoices: venueChoices,
              authors: authors,
              tags: tags,
              citedSources: citedSources,
              tunes: tunes,
              choiceFields: choiceFields,
              booleanFields: const [],
              textFields: textFields,
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

  group('calling-history scopes (N1-H2)', () {
    Finder within(String months) =>
        find.byKey(ValueKey('facet-history-within-$months'));
    final hint = find.byKey(const ValueKey('facet-history-inert-hint'));
    // The section's own count badge, not the panel-wide one.
    Finder badge() => find.descendant(
      of: find.byKey(const ValueKey('facet-row-call-status')),
      matching: find.byType(Badge),
    );

    testWidgets('Within offers 1, 3 and 6 months and a date, never a year', (
      tester,
    ) async {
      await _pump(
        tester,
        FacetSelections(),
        hasCallingHistory: true,
        onChanged: () {},
      );
      expect(find.text('1 month'), findsOneWidget);
      expect(find.text('3 months'), findsOneWidget);
      expect(find.text('6 months'), findsOneWidget);
      expect(find.text('Since a date…'), findsOneWidget);
      expect(find.text('Any time'), findsOneWidget);
      // The chips are exactly these five: no 4 weeks, no 12 months.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('facet-row-call-status')),
          matching: find.byType(ChoiceChip),
        ),
        findsNWidgets(5),
      );
      expect(find.textContaining('year'), findsNothing);
      expect(find.textContaining('week'), findsNothing);
    });

    testWidgets('the no-window choice reads Never called with Not called', (
      tester,
    ) async {
      final facets = FacetSelections();
      await _pump(tester, facets, hasCallingHistory: true, onChanged: () {});
      expect(find.text('Never called'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('call-status-not-called')));
      await tester.pump();
      expect(find.text('Never called'), findsOneWidget);
      expect(find.text('Any time'), findsNothing);

      Future<void> toggleCalled() async {
        await tester.tap(find.byKey(const ValueKey('call-status-called')));
        await tester.pump();
      }

      // Both chosen: the scopes are inert and the label is the neutral one.
      await toggleCalled();
      expect(find.text('Any time'), findsOneWidget);

      // At a venue "never called" would claim more than it means.
      facets.setHistoryVenue(VenueKey.typed('Grange'), label: 'Grange');
      await toggleCalled(); // back to Not called only
      expect(find.text('Never called'), findsNothing);
      expect(find.text('Any time'), findsOneWidget);
    });

    testWidgets('a preset sets the window and Any time clears it', (
      tester,
    ) async {
      final facets = FacetSelections()..callStatuses.add(false);
      var changes = 0;
      await _pump(
        tester,
        facets,
        hasCallingHistory: true,
        onChanged: () => changes++,
      );
      await tester.tap(within('3'));
      await tester.pump();
      expect(facets.historyMonths, 3);
      await tester.tap(within('1'));
      await tester.pump();
      expect(facets.historyMonths, 1);
      await tester.tap(find.byKey(const ValueKey('facet-history-within-none')));
      await tester.pump();
      expect(facets.historyMonths, isNull);
      expect(facets.historySince, isNull);
      expect(changes, 3);
    });

    testWidgets('Since a date opens the date picker and keeps the day', (
      tester,
    ) async {
      final facets = FacetSelections()..callStatuses.add(true);
      await _pump(tester, facets, hasCallingHistory: true, onChanged: () {});
      await tester.tap(within('since'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      expect(facets.historySince, DateTime.utc(now.year, now.month, now.day));
      expect(facets.historyMonths, isNull);
      expect(find.textContaining('Since '), findsOneWidget);
      expect(find.text('Since a date…'), findsNothing);
    });

    testWidgets('without a polarity the scopes are inert and say so', (
      tester,
    ) async {
      final facets = FacetSelections()..setHistoryMonths(3);
      await _pump(tester, facets, hasCallingHistory: true, onChanged: () {});
      expect(hint, findsOneWidget);
      expect(find.text('Applies with Called or Not called'), findsOneWidget);
      expect(badge(), findsNothing);

      await tester.tap(find.byKey(const ValueKey('call-status-called')));
      await tester.pump();
      expect(hint, findsNothing);
      // The window came back with the polarity: 1 polarity + 1 scope.
      expect(facets.historyMonths, 3);
      expect(
        find.descendant(of: badge(), matching: find.text('2')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('call-status-called')));
      await tester.pump();
      expect(hint, findsOneWidget);
      expect(facets.historyMonths, 3, reason: 'the scope stays set');
      expect(badge(), findsNothing);
    });

    testWidgets('the section badge counts each applying scope', (tester) async {
      final facets = FacetSelections()
        ..callStatuses.add(false)
        ..setHistoryVenue(VenueKey.typed('Grange'), label: 'Grange')
        ..setHistoryMonths(6);
      await _pump(tester, facets, hasCallingHistory: true, onChanged: () {});
      expect(
        find.descendant(of: badge(), matching: find.text('3')),
        findsOneWidget,
      );
      expect(find.text('Grange'), findsOneWidget);
    });

    testWidgets(
      'the venue chooser lists counted venues with program counts and marks '
      'a typed one',
      (tester) async {
        final repos = openTestRepositories();
        await repos.dances.create(_dance('d1'));
        await repos.venues.upsert(Venue(id: 'v1', name: 'Town Hall'));
        Program program(
          String id,
          DateTime date, {
          String? venueId,
          String? venue,
        }) => Program(
          id: id,
          title: id,
          eventDate: date,
          venueId: venueId,
          venue: venue,
          slots: [ProgramSlot(id: '$id-s', position: 0, danceId: 'd1')],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
        await repos.programs.create(
          program('p1', DateTime.utc(2026, 3, 1), venueId: 'v1'),
        );
        await repos.programs.create(
          program('p2', DateTime.utc(2026, 4, 1), venueId: 'v1'),
        );
        await repos.programs.create(
          program('p3', DateTime.utc(2026, 5, 1), venue: 'The  Grange'),
        );
        final facets = FacetSelections()..callStatuses.add(false);
        var changes = 0;
        await _pump(
          tester,
          facets,
          hasCallingHistory: true,
          venueChoices: VenueChoiceSource(repos: repos),
          onChanged: () => changes++,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();

        expect(find.text('Any venue'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('facet-history-venue')));
        await tester.pumpAndSettle();
        expect(find.text('Town Hall'), findsOneWidget);
        expect(find.text('2 programs'), findsOneWidget);
        expect(find.text('The Grange'), findsOneWidget);
        expect(find.text('1 program · typed'), findsOneWidget);

        await tester.tap(find.text('The Grange'));
        await tester.pumpAndSettle();
        expect(facets.historyVenue, VenueKey.typed('the grange'));
        expect(facets.historyVenueLabel, 'The Grange');
        expect(changes, 1);

        // The chip now names the venue, and its x clears the scope.
        expect(find.text('The Grange'), findsOneWidget);
        await tester.tap(find.byTooltip('Clear venue'));
        await tester.pump();
        expect(facets.historyVenue, isNull);
        expect(facets.historyVenueLabel, isNull);
      },
    );

    testWidgets('no venue row while no venue has a counted call', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        FacetSelections(),
        hasCallingHistory: true,
        venueChoices: VenueChoiceSource(repos: repos),
        onChanged: () {},
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('facet-history-venue')), findsNothing);
      expect(within('3'), findsOneWidget);
    });
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

  testWidgets('text custom-field clear button carries a tooltip', (
    tester,
  ) async {
    // Every other icon-only button in the panel names itself; an unnamed
    // clear button is announced as just "button" by a screen reader.
    final facets = FacetSelections();
    await _pump(
      tester,
      facets,
      textFields: [
        CustomFieldDef(
          id: 'ft',
          key: 'ft',
          label: 'Notes',
          type: CustomFieldType.text,
        ),
      ],
      onChanged: () {},
    );

    await tester.enterText(
      find.byKey(const ValueKey('cf-text-ft-input')),
      'zesty',
    );
    await tester.pumpAndSettle();
    expect(facets.textValues['ft']?.value, 'zesty');

    final clear = find.byTooltip('Clear filter');
    expect(clear, findsOneWidget);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(facets.textValues.containsKey('ft'), isFalse);
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

  group('Tags match mode (FIND-14)', () {
    final tags = [
      Tag(id: 't1', name: 'smooth'),
      Tag(id: 't2', name: 'energetic'),
      Tag(id: 't3', name: 'zesty'),
    ];
    const toggleKey = ValueKey('facet-tags-match-mode');
    final l10n = AppLocalizationsEn();

    Future<void> tapKey(WidgetTester tester, Key key) async {
      await tester.ensureVisible(find.byKey(key));
      await tester.tap(find.byKey(key));
      await tester.pump();
    }

    testWidgets('the choice appears with the second tag, defaulting to all; '
        'a third tag keeps the chosen mode', (tester) async {
      final facets = FacetSelections();
      var changes = 0;
      await _pump(tester, facets, tags: tags, onChanged: () => changes++);

      expect(find.byKey(toggleKey), findsNothing);
      await tapKey(tester, const ValueKey('tag-t1'));
      expect(find.byKey(toggleKey), findsNothing, reason: 'one tag');

      await tapKey(tester, const ValueKey('tag-t2'));
      expect(find.byKey(toggleKey), findsOneWidget);
      expect(
        tester.widget<SegmentedButton<bool>>(find.byKey(toggleKey)).selected,
        {true},
      );

      await tester.tap(find.text(l10n.collectionFacetTagsMatchAny));
      await tester.pump();
      expect(facets.tagsMatchAll, isFalse);
      expect(changes, 3);

      await tapKey(tester, const ValueKey('tag-t3'));
      expect(facets.tagsMatchAll, isFalse);
      expect(
        tester.widget<SegmentedButton<bool>>(find.byKey(toggleKey)).selected,
        {false},
      );

      // Back to one tag hides it; a new second tag starts at all again.
      await tapKey(tester, const ValueKey('tag-t3'));
      await tapKey(tester, const ValueKey('tag-t2'));
      expect(find.byKey(toggleKey), findsNothing);
      await tapKey(tester, const ValueKey('tag-t2'));
      expect(facets.tagsMatchAll, isTrue);
    });

    testWidgets('Untagged does not count toward showing the choice', (
      tester,
    ) async {
      final facets = FacetSelections()
        ..untagged = true
        ..tagIds.add('t1');
      await _pump(tester, facets, tags: tags, onChanged: () {});
      expect(find.byKey(toggleKey), findsNothing);
    });

    testWidgets('a screen reader hears the choice and each segment', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final facets = FacetSelections()..tagIds.addAll(['t1', 't2']);
      await _pump(tester, facets, tags: tags, onChanged: () {});

      expect(
        find.bySemanticsLabel(l10n.collectionFacetTagsMatchLabel),
        findsOneWidget,
      );
      expect(
        find.byTooltip(l10n.collectionFacetTagsMatchAllTooltip),
        findsOneWidget,
      );
      expect(
        find.byTooltip(l10n.collectionFacetTagsMatchAnyTooltip),
        findsOneWidget,
      );
      handle.dispose();
    });
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

    testWidgets('narrow layout: Enter in the sheet commits the typed text and '
        'closes the sheet (review of #1430)', (tester) async {
      final facets = FacetSelections();
      var changes = 0;
      await _pump(
        tester,
        facets,
        tunes: tunes,
        screenSize: const Size(360, 720),
        onChanged: () => changes++,
      );

      await tester.tap(search, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      // "gmaj" is a substring of the suggestion "Gmaj 6/8" but is not it: the
      // first row is the typed text, which is what Enter must commit.
      await tester.enterText(search, 'gmaj');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(facets.tunes, ['gmaj']);
      expect(changes, 1);
      expect(find.byType(BottomSheet), findsNothing);
      expect(chip('gmaj'), findsOneWidget);
    });

    testWidgets('narrow layout: Enter on a blank field just closes the sheet', (
      tester,
    ) async {
      final facets = FacetSelections();
      var changes = 0;
      await _pump(
        tester,
        facets,
        tunes: tunes,
        screenSize: const Size(360, 720),
        onChanged: () => changes++,
      );

      await tester.tap(search, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.enterText(search, '   ');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(facets.tunes, isEmpty);
      expect(changes, 0);
      expect(find.byType(BottomSheet), findsNothing);
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

  group('untagged chip (issue #1422)', () {
    final smooth = Tag(id: 't1', name: 'smooth');
    final lively = Tag(id: 't2', name: 'lively');

    testWidgets('is absent when the Tags section is absent', (tester) async {
      await _pump(tester, FacetSelections(), onChanged: () {});
      expect(find.byKey(const ValueKey('facet-row-tags')), findsNothing);
      expect(find.byKey(const ValueKey('untagged-chip')), findsNothing);
    });

    testWidgets('is the first chip of the Tags section', (tester) async {
      await _pump(
        tester,
        FacetSelections(),
        tags: [smooth, lively],
        onChanged: () {},
      );
      final chips = find.descendant(
        of: find.byKey(const ValueKey('facet-row-tags')),
        matching: find.byType(FilterChip),
      );
      expect(chips, findsNWidgets(3));
      expect(
        tester.widget<FilterChip>(chips.first).key,
        const ValueKey('untagged-chip'),
      );
      expect(find.text('Untagged'), findsOneWidget);
    });

    testWidgets('a real tag whose id is "untagged" does not collide with it', (
      tester,
    ) async {
      // Tag ids are unvalidated and an archive restore keeps the id it carries,
      // so a real tag can legitimately be id `untagged`.
      final facets = FacetSelections();
      await _pump(
        tester,
        facets,
        tags: [
          Tag(id: 'untagged', name: 'Odd one'),
          smooth,
        ],
        onChanged: () {},
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('untagged-chip')), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-untagged')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tag-untagged')));
      await tester.pump();
      expect(facets.tagIds, {'untagged'});
      expect(facets.untagged, isFalse, reason: 'the real tag is not Untagged');

      await tester.tap(find.byKey(const ValueKey('untagged-chip')));
      await tester.pump();
      expect(facets.untagged, isTrue);
      expect(facets.tagIds, {'untagged'});
    });

    testWidgets('toggles independently of the tag chips', (tester) async {
      final facets = FacetSelections();
      await _pump(tester, facets, tags: [smooth, lively], onChanged: () {});

      await tester.tap(find.byKey(const ValueKey('untagged-chip')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tag-t1')));
      await tester.pump();
      expect(facets.untagged, isTrue);
      expect(facets.tagIds, {'t1'});

      await tester.tap(find.byKey(const ValueKey('tag-t1')));
      await tester.pump();
      expect(facets.untagged, isTrue, reason: 'a tag chip must not clear it');
      expect(facets.tagIds, isEmpty);

      await tester.tap(find.byKey(const ValueKey('tag-t2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('untagged-chip')));
      await tester.pump();
      expect(facets.untagged, isFalse);
      expect(facets.tagIds, {'t2'}, reason: 'Untagged must not clear tags');
    });

    testWidgets('counts toward the Tags section badge', (tester) async {
      final facets = FacetSelections();
      await _pump(tester, facets, tags: [smooth, lively], onChanged: () {});
      expect(find.byType(Badge), findsNothing);

      await tester.tap(find.byKey(const ValueKey('untagged-chip')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tag-t1')));
      await tester.pump();

      final badge = find.byType(Badge);
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('Untagged + a tag compiles to one OR group', (tester) async {
      final facets = FacetSelections();
      await _pump(tester, facets, tags: [smooth, lively], onChanged: () {});
      await tester.tap(find.byKey(const ValueKey('untagged-chip')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tag-t1')));
      await tester.pump();

      final f = buildCollectionFilter(ftsText: '', facets: facets, defs: []);
      expect(f, isA<OrFilter>());
      expect((f as OrFilter).children.map((c) => c.runtimeType).toSet(), {
        TagFilter,
        UntaggedFilter,
      });
    });
  });
}

Dance _dance(String id) => Dance(
  id: id,
  title: id,
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  progression: Progression.single,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
