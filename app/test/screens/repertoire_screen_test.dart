import 'package:clock/clock.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/show_repertoire_scope.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/screens/repertoire_screen.dart';
import 'package:compendium_app/src/search/repertoire_drill_down.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// The Repertoire page (#2357): its drill-downs land in Collection with the
/// filter the issue states, each row reads as one sentence, and the page holds
/// up at the largest text size and in the High contrast theme.
void main() {
  final today = DateTime(2026, 11, 22, 10);
  // Calls in the last three months of [today] start here.
  final cutoff = DateTime.utc(2026, 8, 22);

  Future<CompendiumRepositories> seeded() async {
    final repos = openTestRepositories();
    final at = DateTime.utc(2026, 1, 1);
    final _ = await repos.choreographers.upsert(
      Choreographer(id: 'kaynor', name: 'Kaynor'),
    );
    final _ = await repos.choreographers.upsert(
      Choreographer(id: 'dart', name: 'Dart'),
    );
    await repos.venues.upsert(Venue(id: 'hall', name: 'Town Hall'));
    Future<void> dance(
      String id,
      String title, {
      DanceForm form = DanceForm.contra,
      FormationShape shape = FormationShape.dupleImproper,
      List<String> authors = const [],
      List<Figure> figures = const [],
    }) => repos.dances.create(
      Dance(
        id: id,
        title: title,
        form: form,
        formation: Formation(shape),
        authorIds: authors,
        figures: figures,
        createdAt: at,
        updatedAt: at,
      ),
    );
    await dance(
      'petronella',
      'Petronella',
      authors: ['kaynor'],
      figures: [
        Figure(move: 'swing'),
        Figure(move: 'allemande'),
        Figure(move: 'swing'),
      ],
    );
    await dance(
      'becket',
      'Becket Reel',
      shape: FormationShape.becketCw,
      authors: ['dart'],
      figures: [Figure(move: 'swing')],
    );
    await dance('never', 'Never Danced', figures: [Figure(move: 'swing')]);
    await dance(
      'rose',
      'Rose Tree',
      form: DanceForm.ecd,
      shape: FormationShape.longways,
      figures: [Figure(move: 'swing')],
    );
    var seq = 0;
    Future<void> program(
      String id,
      DateTime eventDate,
      List<String> danceIds, {
      String? venueId,
      String? venue,
    }) => repos.programs.create(
      Program(
        id: id,
        title: id,
        eventDate: eventDate,
        venueId: venueId,
        venue: venue,
        slots: [
          for (final d in danceIds)
            ProgramSlot(id: 's${seq++}', position: seq, danceId: d),
        ],
        createdAt: at,
        updatedAt: at,
      ),
    );
    await program(
      'p1',
      DateTime.utc(2026, 11, 1),
      ['petronella', 'becket'],
      venueId: 'hall',
      venue: 'Town Hall',
    );
    await program(
      'p2',
      DateTime.utc(2026, 11, 8),
      ['petronella'],
      venueId: 'hall',
      venue: 'Town Hall',
    );
    // On the three-month boundary, and one day outside it.
    await program('p3', cutoff, ['becket'], venue: 'Grange');
    await program('p4', cutoff.subtract(const Duration(days: 1)), [
      'rose',
    ], venue: 'Grange');
    return repos;
  }

  /// Mounts Collection, as the app does, with the Repertoire switch on and
  /// the clock at [today].
  Future<void> pumpCollection(
    WidgetTester tester,
    CompendiumRepositories repos, {
    Size size = const Size(1000, 2400),
    bool showRepertoire = true,
    double textScale = 1,
    AppThemeSelection themeSelection = AppThemeSelection.system,
    Widget? home,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(dialect.dispose);
    final theme = ValueNotifier<AppThemeSelection>(themeSelection);
    addTearDown(theme.dispose);
    final show = ValueNotifier<bool>(showRepertoire);
    addTearDown(show.dispose);
    final customThemes = CustomThemesController(repos.settings);
    await customThemes.load();
    addTearDown(customThemes.dispose);
    await withClock(
      Clock.fixed(today),
      () => tester.pumpWidget(
        MaterialApp(
          theme: themeSelection.isHighContrast ? AppTheme.highContrast : null,
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: RepositoriesScope(
              repositories: repos,
              child: AppThemeScope(
                notifier: theme,
                child: CustomThemesScope(
                  controller: customThemes,
                  child: ActiveDialectScope(
                    notifier: dialect,
                    child: ShowRepertoireScope(notifier: show, child: child!),
                  ),
                ),
              ),
            ),
          ),
          home: home ?? const DanceListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openRepertoire(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('collection-more-actions')));
    await tester.pumpAndSettle();
    await withClock(Clock.fixed(today), () async {
      await tester.tap(find.byKey(const ValueKey('collection-repertoire')));
      await tester.pumpAndSettle();
    });
    expect(find.byType(RepertoireScreen), findsOneWidget);
  }

  Future<void> tapRow(WidgetTester tester, String key) async {
    final row = find.byKey(ValueKey(key));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('repertoire-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await withClock(Clock.fixed(today), () async {
      await tester.tap(row);
      await tester.pumpAndSettle();
    });
  }

  Set<String> listedTitles(WidgetTester tester) => {
    for (final tile in tester.widgetList<DanceListTile>(
      find.byType(DanceListTile),
    ))
      tile.entry.title,
  };

  group('the More actions entry', () {
    testWidgets('is absent while the switch is off', (tester) async {
      final repos = await seeded();
      await pumpCollection(tester, repos, showRepertoire: false);
      await tester.tap(find.byKey(const ValueKey('collection-more-actions')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recently-deleted')), findsOneWidget);
      expect(find.byKey(const ValueKey('collection-repertoire')), findsNothing);
    });

    testWidgets('opens the page as a pushed route; Back returns', (
      tester,
    ) async {
      final repos = await seeded();
      await pumpCollection(tester, repos);
      await openRepertoire(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(RepertoireScreen), findsNothing);
      expect(find.byType(DanceListScreen), findsOneWidget);
    });
  });

  group('each drill-down opens Collection with its filter', () {
    Future<Set<String>> drill(
      WidgetTester tester,
      String rowKey, {
      String? periodKey,
    }) async {
      final repos = await seeded();
      await pumpCollection(tester, repos);
      await openRepertoire(tester);
      if (periodKey != null) {
        await withClock(Clock.fixed(today), () async {
          await tester.tap(find.byKey(ValueKey(periodKey)));
          await tester.pumpAndSettle();
        });
      }
      await tapRow(tester, rowKey);
      expect(find.byType(RepertoireScreen), findsNothing);
      return listedTitles(tester);
    }

    testWidgets('Never called: not called, never', (tester) async {
      expect(await drill(tester, 'repertoire-never-called'), {'Never Danced'});
    });

    testWidgets('Not called in this period: not called, within', (
      tester,
    ) async {
      // The Collection dates its Within window by the device clock, so only
      // what holds on any date after the fixture's calls is asserted.
      final titles = await drill(
        tester,
        'repertoire-not-called-in-period',
        periodKey: 'repertoire-period-1',
      );
      // Never called, and called only before any one-month window that
      // includes the test fixture's November calls.
      expect(titles, containsAll(['Never Danced', 'Rose Tree']));
    });

    testWidgets('a figure: that type AND has the figure', (tester) async {
      expect(await drill(tester, 'repertoire-figure-contra-allemande'), {
        'Petronella',
      });
    });

    testWidgets('a figure of another type keeps that type', (tester) async {
      expect(await drill(tester, 'repertoire-figure-ecd-swing'), {'Rose Tree'});
    });

    testWidgets('a choreographer: author AND called', (tester) async {
      expect(await drill(tester, 'repertoire-author-dart'), {'Becket Reel'});
    });

    testWidgets('a formation: formation AND called', (tester) async {
      expect(await drill(tester, 'repertoire-formation-becketCw'), {
        'Becket Reel',
      });
    });

    testWidgets('a venue: called at that venue', (tester) async {
      expect(await drill(tester, 'repertoire-venue-id:hall'), {
        'Petronella',
        'Becket Reel',
      });
    });

    testWidgets('replaces the search already in Collection', (tester) async {
      final repos = await seeded();
      await pumpCollection(tester, repos);
      await tester.enterText(find.byType(TextField).first, 'Becket');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(listedTitles(tester), {'Becket Reel'});
      await openRepertoire(tester);
      await tapRow(tester, 'repertoire-never-called');
      // Kept, the text would leave nothing: Becket Reel has been called.
      expect(listedTitles(tester), {'Never Danced'});
    });

    testWidgets('a dance opens that dance', (tester) async {
      final repos = await seeded();
      await pumpCollection(tester, repos);
      await openRepertoire(tester);
      await tapRow(tester, 'repertoire-most-petronella');
      expect(find.byType(DanceDetailScreen), findsOneWidget);
    });
  });

  group('the drill-down is the stated DanceFilter', () {
    String describe(DanceFilter f) => switch (f) {
      AndFilter(:final children) => 'AND(${children.map(describe).join(', ')})',
      OrFilter(:final children) => 'OR(${children.map(describe).join(', ')})',
      FormFilter(:final form) => 'form=${form.name}',
      FormationFilter(:final shape) => 'formation=${shape.name}',
      AuthorFilter(:final choreographerId) => 'author=$choreographerId',
      FigureFilter(query: FigureLeaf(:final move, :final section)) =>
        'figure=$move${section == null ? '' : '@$section'}',
      CalledFilter(:final called, :final since, :final venue) =>
        'called=$called'
            '${since == null ? '' : ' since=${since.toIso8601String()}'}'
            '${venue == null ? '' : ' venue=${venue.storageKey}'}',
      _ => f.runtimeType.toString(),
    };

    String built(RepertoireDrillDown d) {
      final facets = FacetSelections();
      final advanced = BuilderGroup();
      d.applyTo(facets, advanced);
      return describe(
        buildCollectionFilter(
          ftsText: '',
          facets: facets,
          defs: const [],
          advancedRoot: advanced,
          today: today,
        ),
      );
    }

    const three = RepertoirePeriod.months(3);
    final since = cutoff.toIso8601String();
    test('for every section', () {
      expect(built(const RepertoireDrillDown.neverCalled()), 'called=false');
      expect(
        built(const RepertoireDrillDown.notCalledIn(three)),
        'called=false since=$since',
      );
      expect(
        built(
          const RepertoireDrillDown.figure('swing', form: DanceForm.contra),
        ),
        'AND(form=contra, figure=swing)',
      );
      expect(
        built(const RepertoireDrillDown.author('dart', three)),
        'AND(called=true since=$since, author=dart)',
      );
      expect(
        built(
          const RepertoireDrillDown.formation(FormationShape.becketCw, three),
        ),
        'AND(formation=becketCw, called=true since=$since)',
      );
      expect(
        built(RepertoireDrillDown.venue(const VenueKey.record('hall'), three)),
        'called=true since=$since venue=id:hall',
      );
      expect(
        built(
          const RepertoireDrillDown.author(
            'dart',
            RepertoirePeriod.allTime(),
            form: DanceForm.ecd,
          ),
        ),
        'AND(form=ecd, called=true, author=dart)',
      );
    });

    test('a period gives the cutoff the Within window gives', () {
      for (final months in RepertoirePeriod.monthPresets) {
        final facets = FacetSelections()..setHistoryMonths(months);
        expect(
          RepertoirePeriod.months(months).cutoff(today),
          facets.historyCutoff(today),
        );
      }
      final picked = DateTime(2026, 3, 14, 18);
      expect(
        RepertoirePeriod.since(picked).cutoff(today),
        (FacetSelections()..setHistorySince(picked)).historyCutoff(today),
      );
    });
  });

  group('the period', () {
    testWidgets('a call on the window\'s first day counts, one a day '
        'earlier does not, as with CalledFilter.since', (tester) async {
      final repos = await seeded();
      await pumpCollection(tester, repos, home: const RepertoireScreen());
      await withClock(Clock.fixed(today), () async {
        await tester.tap(find.byKey(const ValueKey('repertoire-period-3')));
        await tester.pumpAndSettle();
      });
      // Becket Reel's only call in the window is on its first day.
      expect(
        find.byKey(const ValueKey('repertoire-most-becket')),
        findsOneWidget,
      );
      // Rose Tree's only call is the day before.
      expect(find.byKey(const ValueKey('repertoire-most-rose')), findsNothing);

      final calledSince = await repos.dances.search(
        CalledFilter(called: true, since: cutoff),
      );
      expect(calledSince.toSet(), {'petronella', 'becket'});
    });
  });

  group('accessibility', () {
    testWidgets('each row is one label carrying its number; bars are not '
        'read', (tester) async {
      final semantics = tester.ensureSemantics();
      final repos = await seeded();
      await pumpCollection(tester, repos, home: const RepertoireScreen());

      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('repertoire-most-petronella')),
        ),
        matchesSemantics(
          label: 'Petronella: called 2 times',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('repertoire-figure-contra-swing')),
        ),
        matchesSemantics(
          label: 'swing: in 3 of 3 dances, 100 percent; 4 calls in this period',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('repertoire-never-called')),
        ),
        matchesSemantics(
          label: 'Never called: 1 of 4 dances',
          isButton: true,
          hasTapAction: true,
        ),
      );
      // A bar adds no node of its own: every row's node is a leaf, and the
      // node a bar belongs to is its row's.
      for (final row in find.byType(StatRow).evaluate()) {
        final node = tester.getSemantics(find.byWidget(row.widget));
        expect(node.childrenCount, 0, reason: node.label);
        expect(node.label, isNot(isEmpty));
      }
      for (final bar in find.byType(ProportionBar).evaluate()) {
        final node = tester.getSemantics(find.byWidget(bar.widget));
        expect(
          find.byWidgetPredicate(
            (w) => w is StatRow && w.semanticsLabel == node.label,
          ),
          findsWidgets,
        );
      }
      semantics.dispose();
    });

    testWidgets('a row activates with Enter', (tester) async {
      final repos = await seeded();
      await pumpCollection(tester, repos);
      await openRepertoire(tester);
      final row = find.byKey(const ValueKey('repertoire-never-called'));
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('repertoire-list')),
          matching: find.byType(Scrollable),
        ),
      );
      // The row's own focus node, the one InkWell puts above its content.
      Focus.of(
        tester.element(
          find.descendant(of: row, matching: find.byType(Padding)).first,
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(RepertoireScreen), findsNothing);
      expect(listedTitles(tester), {'Never Danced'});
    });

    for (final (name, selection) in [
      ('system', AppThemeSelection.system),
      ('High contrast', AppThemeSelection.highContrast),
    ]) {
      for (final scale in [2.0, 3.0]) {
        testWidgets('no overflow at ${scale}x text, $name theme, 360 dp', (
          tester,
        ) async {
          final repos = await seeded();
          await pumpCollection(
            tester,
            repos,
            size: const Size(360, 4000),
            textScale: scale,
            themeSelection: selection,
            home: const RepertoireScreen(),
          );
          expect(tester.takeException(), isNull);
          // Rows grow with the text: none is clipped to a fixed height.
          final row = find.byKey(const ValueKey('repertoire-most-petronella'));
          final text = find.descendant(
            of: row,
            matching: find.text('Petronella'),
          );
          expect(
            tester.getSize(row).height,
            greaterThan(tester.getSize(text).height),
          );
          if (selection.isHighContrast) {
            final bar = tester.widget<Container>(
              find
                  .descendant(
                    of: find.byType(ProportionBar).first,
                    matching: find.byType(Container),
                  )
                  .first,
            );
            final decoration = bar.decoration! as BoxDecoration;
            expect(decoration.border, isNotNull, reason: 'HC outline');
          }
        });
      }
    }
  });
}
