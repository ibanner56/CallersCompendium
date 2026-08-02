import 'package:compendium_app/src/search/collection_query.dart';
import 'package:compendium_app/src/search/facet_labels.dart';
import 'package:compendium_app/src/widgets/advanced_query_builder.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/l10n_harness.dart';
import '../support/screen_size.dart';

// ---------------------------------------------------------------------------
// Minimal host that owns the mutable builder root and calls onChanged to
// rebuild — mirrors the Collection screen's usage.
// ---------------------------------------------------------------------------

class _Host extends StatefulWidget {
  const _Host({
    required this.root,
    required this.sectionLabels,
    required this.taxonomy,
    required this.dialect,
  });
  final BuilderGroup root;
  final List<String> sectionLabels;
  final Taxonomy taxonomy;
  final Dialect dialect;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdvancedQueryBuilder(
            root: widget.root,
            taxonomy: widget.taxonomy,
            dialect: widget.dialect,
            sectionLabels: widget.sectionLabels,
            onChanged: () => setState(() {}),
          ),
        ),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required BuilderGroup root,
  List<String> sectionLabels = const [],
  // Comfortably above ResponsiveAutocomplete's compact width/height
  // breakpoints (600/480) so the "has figure" move field's wide inline
  // overlay renders by default, matching every test written before that
  // field existed. Pass a narrow/short size (e.g. Size(360, 720)) to
  // exercise the sheet path instead.
  Size screenSize = const Size(900, 1600),
  // Defaults to the real taxonomy, which is what every test here wants.
  // Overridden only by the `spec.choices` facet tests below, which need a
  // param combination no live taxonomy param declares yet.
  Taxonomy? taxonomy,
  // Defaults to the app's own default dialect. Overridden by the labelling
  // tests, which assert the facet honours the user's role terminology.
  Dialect? dialect,
}) async {
  await setScreenSize(tester, screenSize);
  await tester.pumpWidget(
    _Host(
      root: root,
      sectionLabels: sectionLabels,
      taxonomy: taxonomy ?? contraTaxonomy,
      dialect: dialect ?? Dialect.larksRobins,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // -------------------------------------------------------------------------
  // _ThenRow basic rendering
  // -------------------------------------------------------------------------

  group('_ThenRow basic rendering', () {
    testWidgets('renders First / then / Later labels', (tester) async {
      final root = BuilderGroup(children: [BuilderThen()]);
      await _pump(tester, root: root);

      expect(find.text('First'), findsOneWidget);
      expect(find.text('then'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('each side shows "Group figures" button by default', (
      tester,
    ) async {
      final root = BuilderGroup(children: [BuilderThen()]);
      await _pump(tester, root: root);

      expect(find.text('Group figures'), findsNWidgets(2));
    });
  });

  // -------------------------------------------------------------------------
  // Grouping a then operand
  // -------------------------------------------------------------------------

  group('grouping a then operand', () {
    testWidgets('tapping "Group figures" on First side shows group editor', (
      tester,
    ) async {
      final thenNode = BuilderThen();
      final root = BuilderGroup(children: [thenNode]);
      await _pump(tester, root: root);

      // Tap the first "Group figures" button (the "First" side)
      final groupButtons = find.text('Group figures');
      await tester.tap(groupButtons.first);
      await tester.pumpAndSettle();

      // Group editor shows kind dropdown ("Any of") and "Add figure" button
      expect(find.text('of these figures'), findsOneWidget);
      expect(find.text('Add figure'), findsOneWidget);
      // The original figure is now inside the group — "Group figures" on that
      // side is gone; the other side (Later) still has it.
      expect(find.text('Group figures'), findsOneWidget);
    });

    testWidgets(
      'after grouping, fold produces ThenFilter with FigureOr-able before',
      (tester) async {
        final thenNode = BuilderThen(
          before: BuilderFigure(move: 'swing'),
          after: BuilderFigure(move: 'chain'),
        );
        final root = BuilderGroup(children: [thenNode]);
        await _pump(tester, root: root);

        // Tap the first "Group figures" (First side)
        await tester.tap(find.text('Group figures').first);
        await tester.pumpAndSettle();

        // The before side is now a BuilderFigureGroup wrapping 'swing'
        expect(thenNode.before, isA<BuilderFigureGroup>());
        final group = thenNode.before as BuilderFigureGroup;
        expect(group.children, hasLength(1));
        expect(group.children.single, isA<BuilderFigure>());

        // Fold still produces a valid ThenFilter because the group has one leaf
        final f = thenNode.toFilter();
        expect(f, isA<ThenFilter>());
        final tf = f as ThenFilter;
        // Single-child group unwraps → FigureLeaf (not FigureOr)
        expect(tf.before, isA<FigureLeaf>());
        expect((tf.before as FigureLeaf).move, 'swing');
      },
    );

    testWidgets('"Add figure" adds a second leaf to the group', (tester) async {
      final thenNode = BuilderThen(
        before: BuilderFigure(move: 'swing'),
        after: BuilderFigure(move: 'chain'),
      );
      final root = BuilderGroup(children: [thenNode]);
      await _pump(tester, root: root);

      await tester.tap(find.text('Group figures').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add figure'));
      await tester.pumpAndSettle();

      final group = thenNode.before as BuilderFigureGroup;
      expect(group.children, hasLength(2));
    });
  });

  // -------------------------------------------------------------------------
  // Flattening back to single figure
  // -------------------------------------------------------------------------

  group('flatten group back to single figure', () {
    testWidgets('"Single figure" button appears only for a single-leaf group', (
      tester,
    ) async {
      final thenNode = BuilderThen(
        before: BuilderFigureGroup(
          kind: GroupKind.any,
          children: [BuilderFigure(move: 'swing')],
        ),
        after: BuilderFigure(move: 'chain'),
      );
      final root = BuilderGroup(children: [thenNode]);
      await _pump(tester, root: root);

      expect(find.text('Single figure'), findsOneWidget);
    });

    testWidgets('"Single figure" is absent for a multi-leaf group', (
      tester,
    ) async {
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
      final root = BuilderGroup(children: [thenNode]);
      await _pump(tester, root: root);

      expect(find.text('Single figure'), findsNothing);
    });

    testWidgets('tapping "Single figure" reverts to a BuilderFigure', (
      tester,
    ) async {
      final figure = BuilderFigure(move: 'swing');
      final thenNode = BuilderThen(
        before: BuilderFigureGroup(kind: GroupKind.any, children: [figure]),
        after: BuilderFigure(move: 'chain'),
      );
      final root = BuilderGroup(children: [thenNode]);
      await _pump(tester, root: root);

      await tester.tap(find.text('Single figure'));
      await tester.pumpAndSettle();

      expect(thenNode.before, isA<BuilderFigure>());
      expect(thenNode.before, same(figure));
      // Group figures button returns
      expect(find.text('Group figures'), findsNWidgets(2));
    });
  });

  // -------------------------------------------------------------------------
  // Kind dropdown in the group editor
  // -------------------------------------------------------------------------

  group('group kind dropdown', () {
    testWidgets('kind dropdown shows All of / Any of / None of', (
      tester,
    ) async {
      final thenNode = BuilderThen(
        before: BuilderFigureGroup(kind: GroupKind.any, children: []),
        after: BuilderFigure(move: 'chain'),
      );
      final root = BuilderGroup(children: [thenNode]);
      await _pump(tester, root: root);

      // Open the kind dropdown
      final dropdown = find.byKey(
        ValueKey(
          'fig-group-kind-${(thenNode.before as BuilderFigureGroup).id}',
        ),
      );
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      expect(find.text('All of'), findsWidgets);
      expect(find.text('Any of'), findsWidgets);
      expect(find.text('None of'), findsWidgets);
    });

    testWidgets('changing kind to "all of" updates the model', (tester) async {
      final group = BuilderFigureGroup(kind: GroupKind.any, children: []);
      final thenNode = BuilderThen(
        before: group,
        after: BuilderFigure(move: 'chain'),
      );
      final root = BuilderGroup(children: [thenNode]);
      await _pump(tester, root: root);

      final dropdown = find.byKey(ValueKey('fig-group-kind-${group.id}'));
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      await tester.tap(find.text('All of').last);
      await tester.pumpAndSettle();

      expect(group.kind, GroupKind.all);
    });
  });

  // -------------------------------------------------------------------------
  // Remove a figure leaf inside a group
  // -------------------------------------------------------------------------

  group('removing a figure from a group', () {
    testWidgets('close button on a leaf removes it from the group', (
      tester,
    ) async {
      final leaf = BuilderFigure(move: 'swing');
      final group = BuilderFigureGroup(
        kind: GroupKind.any,
        children: [
          leaf,
          BuilderFigure(move: 'balance'),
        ],
      );
      final thenNode = BuilderThen(
        before: group,
        after: BuilderFigure(move: 'chain'),
      );
      final root = BuilderGroup(children: [thenNode]);
      await _pump(tester, root: root);

      await tester.tap(find.byKey(ValueKey('remove-fig-${leaf.id}')));
      await tester.pumpAndSettle();

      expect(group.children, hasLength(1));
      expect(group.children.single, isA<BuilderFigure>());
    });
  });

  // -------------------------------------------------------------------------
  // Narrow-mode "has figure" move field (issue #716): MoveTypeAheadField's
  // migration to ResponsiveAutocomplete, plus its new fieldKey capability.
  // -------------------------------------------------------------------------

  group('narrow-mode "has figure" move field (#716)', () {
    testWidgets(
      'on a narrow/short screen, picking a move from the keyboard-safe sheet '
      'updates the figure and closes the sheet, with the option fully '
      'visible above a simulated keyboard inset',
      (tester) async {
        final figure = BuilderFigure(move: 'swing');
        final thenNode = BuilderThen(
          before: figure,
          after: BuilderFigure(move: 'balance'),
        );
        final root = BuilderGroup(children: [thenNode]);
        await _pump(tester, root: root, screenSize: const Size(360, 720));

        final fieldKey = ValueKey('has-figure-${figure.id}-input');
        await tester.tap(find.byKey(fieldKey), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);

        // Simulate a software keyboard inset, as issue #716 describes.
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(fieldKey), 'chain');
        await tester.pumpAndSettle();

        final optionKey = ValueKey('has-figure-${figure.id}-option-chain');
        final option = find.byKey(optionKey);
        expect(option, findsOneWidget);
        final optionRect = tester.getRect(option);
        final screenHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        expect(optionRect.bottom, lessThanOrEqualTo(screenHeight - 300));

        await tester.tap(option);
        await tester.pumpAndSettle();

        expect(figure.move, 'chain');
        // Picking always closes the sheet (owner's Q1 decision, uniform
        // across all seven call sites).
        expect(find.byType(BottomSheet), findsNothing);
      },
    );

    testWidgets(
      'the wide layout is unaffected: no sheet opens and the inline overlay '
      'still filters/selects as before',
      (tester) async {
        final figure = BuilderFigure(move: 'swing');
        final thenNode = BuilderThen(
          before: figure,
          after: BuilderFigure(move: 'balance'),
        );
        final root = BuilderGroup(children: [thenNode]);
        await _pump(tester, root: root);

        final fieldKey = ValueKey('has-figure-${figure.id}-input');
        await tester.enterText(find.byKey(fieldKey), 'chain');
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsNothing);
        final optionKey = ValueKey('has-figure-${figure.id}-option-chain');
        expect(find.byKey(optionKey), findsOneWidget);

        await tester.tap(find.byKey(optionKey));
        await tester.pumpAndSettle();

        expect(figure.move, 'chain');
      },
    );
  });

  _paramChoiceTests();
}

// ---------------------------------------------------------------------------
// The "has figure" param dropdowns: domain, and how it is presented
//
// `figureParamChoices` (app/lib/src/search/facet_labels.dart) is the third
// consumer of the `ParamSpec.kind` + `ParamSpec.choices` contract, after the
// figure param editor and `ParamSpec.validate` (both taught the same rule by
// issue #726 / PR #736). It hardcoded the vocabulary for five kinds, so a spec
// that NARROWED its kind's domain got a search dropdown offering the values it
// had just excluded — a filter for a value the param cannot hold.
//
// Issue #741 then separated DOMAIN from SELECTABLE. `figureParamChoices` and
// `ParamSpec.validate` still report and accept the full domain, sentinel
// included — that contract is untouched — but the facet renders only the
// values a caller can meaningfully search for. The sentinel is dropped,
// because it sits directly below "Any <param>", reads like a synonym of it,
// and filters for the near-inverse set.
//
// No live taxonomy param pairs one of those kinds with a `choices` list, so
// these tests inject a synthetic single-move taxonomy. Unit coverage of the
// pure functions is in `test/search/facet_param_choices_test.dart`; the tests
// below exist because those functions are pure — only a widget test proves the
// value reaches the dropdown and round-trips into `BuilderFigure.params`.
// ---------------------------------------------------------------------------

Taxonomy _taxonomyWithHandParam({required List<String>? choices}) => Taxonomy(
  version: 1,
  form: DanceForm.contra,
  moves: [
    MoveDef(
      id: 'wave',
      displayName: 'Wave',
      renderTemplate: '{move} {hand}',
      params: {
        'hand': ParamSpec(
          ParamKind.handedness,
          defaultValue: 'right',
          choices: choices,
        ),
      },
    ),
  ],
);

void _paramChoiceTests() {
  group('has-figure param dropdowns honour spec.choices', () {
    testWidgets('a sentinel in choices is NOT offered (issue #741)', (
      tester,
    ) async {
      // INVERTED from PR #746, which asserted the sentinel was offered and
      // round-tripped. The owner has since ruled it must never be selectable:
      // "As a user I don't want to see 'unspecified' as a drop-down option in
      // the search […] it's meaningless to a user in basically every scenario."
      //
      // The two adjacent options are near-inverses. "Any hand" declines to
      // filter and matches every wave; the sentinel filters FOR waves whose
      // source stated no hand, a drastically smaller set. Both read as "I'm not
      // specifying", with nothing to signal that one of them narrows.
      final figure = BuilderFigure(move: 'wave');
      final root = BuilderGroup(
        children: [BuilderThen(before: figure, after: BuilderFigure())],
      );
      await _pump(
        tester,
        root: root,
        taxonomy: _taxonomyWithHandParam(
          choices: const [...ParamVocab.sides, ParamVocab.unspecified],
        ),
      );

      await tester.tap(find.byKey(ValueKey('param-${figure.id}-hand')));
      await tester.pumpAndSettle();
      expect(find.text(ParamVocab.unspecified), findsNothing);
      // Nor under its human label — the point is that the concept is absent
      // here, not that the wording changed.
      expect(find.text('not stated'), findsNothing);
      // The rest of the domain is unaffected: this removes one option, it does
      // not disable the dropdown.
      expect(find.text('left'), findsWidgets);
      expect(find.text('right'), findsWidgets);
    });

    testWidgets('the sentinel stays in the DOMAIN the facet is handed', (
      tester,
    ) async {
      // Guards the boundary of the fix. `figureParamChoices` and
      // `ParamSpec.validate` are two of the three consumers of one domain
      // contract (#726 / #746) and must keep reporting/accepting the sentinel;
      // only the presentation edge filters it. Asserting this here, next to the
      // widget test above, is what stops a future "simplification" from
      // deleting the sentinel out of the domain and breaking the editor's
      // unstated state along with it.
      const spec = ParamSpec(
        ParamKind.handedness,
        defaultValue: 'right',
        choices: [...ParamVocab.sides, ParamVocab.unspecified],
      );
      expect(figureParamChoices(spec), contains(ParamVocab.unspecified));
      expect(spec.validate(ParamVocab.unspecified), isTrue);
      expect(
        figureParamSelectableChoices(figureParamChoices(spec)!),
        isNot(contains(ParamVocab.unspecified)),
      );
    });

    testWidgets('a param whose whole domain is the sentinel renders nothing', (
      tester,
    ) async {
      // Nothing left to pick, so the dropdown could only ever offer "Any hand"
      // — which is not a filter. An inert control is worse than no control.
      final figure = BuilderFigure(move: 'wave');
      final root = BuilderGroup(
        children: [BuilderThen(before: figure, after: BuilderFigure())],
      );
      await _pump(
        tester,
        root: root,
        taxonomy: _taxonomyWithHandParam(
          choices: const [ParamVocab.unspecified],
        ),
      );

      expect(find.byKey(ValueKey('param-${figure.id}-hand')), findsNothing);
    });

    testWidgets('a narrowed domain does not offer the excluded value', (
      tester,
    ) async {
      final figure = BuilderFigure(move: 'wave');
      final root = BuilderGroup(
        children: [BuilderThen(before: figure, after: BuilderFigure())],
      );
      await _pump(
        tester,
        root: root,
        taxonomy: _taxonomyWithHandParam(choices: const ['right']),
      );

      await tester.tap(find.byKey(ValueKey('param-${figure.id}-hand')));
      await tester.pumpAndSettle();
      // `left` is in `ParamVocab.sides` but NOT in this param's domain, and
      // `ParamSpec.validate` rejects it — offering it would build a filter no
      // valid figure can match.
      expect(find.text('left'), findsNothing);
      expect(find.text('right'), findsWidgets);
    });

    testWidgets('a spec without choices keeps the full fixed vocabulary', (
      tester,
    ) async {
      final figure = BuilderFigure(move: 'wave');
      final root = BuilderGroup(
        children: [BuilderThen(before: figure, after: BuilderFigure())],
      );
      await _pump(
        tester,
        root: root,
        taxonomy: _taxonomyWithHandParam(choices: null),
      );

      await tester.tap(find.byKey(ValueKey('param-${figure.id}-hand')));
      await tester.pumpAndSettle();
      expect(find.text('left'), findsWidgets);
      expect(find.text('right'), findsWidgets);
      // A real value still round-trips into the model as the canonical token.
      await tester.tap(find.text('left').last);
      await tester.pumpAndSettle();
      expect(figure.params['hand'], 'left');
    });
  });

  // -------------------------------------------------------------------------
  // Humanized, dialect-aware labels (issue #741)
  //
  // The facet used to render `Text(choice)` and interpolate the raw param key,
  // so it showed `role1s` and "Any meetTarget" while `FigureParamEditor` showed
  // "larks" and "meet target" for the very same spec. Both surfaces now go
  // through `figureParamChoiceLabel` / `figureParamKeyLabel`, so they cannot
  // drift again.
  // -------------------------------------------------------------------------
  group('has-figure param dropdowns are humanized and dialect-aware', () {
    /// A "hey"-shaped move: one dancerSet param carrying the sentinel, exactly
    /// like the shipped `hey.meetTarget`.
    Taxonomy taxonomyWithMeetTarget() => Taxonomy(
      version: 1,
      form: DanceForm.contra,
      moves: [
        MoveDef(
          id: 'hey',
          displayName: 'Hey',
          renderTemplate: '{move} {meetTarget}',
          params: {
            'meetTarget': ParamSpec(
              ParamKind.dancerSet,
              defaultValue: ParamVocab.unspecified,
              choices: const [
                'role1s',
                'role2s',
                // Multi-word on purpose: `neighbors` humanizes to itself, so an
                // assertion on it would pass with or without the fix.
                'prevNeighbors',
                ParamVocab.unspecified,
              ],
            ),
          },
        ),
      ],
    );

    Future<BuilderFigure> pumpHey(WidgetTester tester, Dialect dialect) async {
      final figure = BuilderFigure(move: 'hey');
      await _pump(
        tester,
        root: BuilderGroup(
          children: [BuilderThen(before: figure, after: BuilderFigure())],
        ),
        taxonomy: taxonomyWithMeetTarget(),
        dialect: dialect,
      );
      await tester.tap(find.byKey(ValueKey('param-${figure.id}-meetTarget')));
      await tester.pumpAndSettle();
      return figure;
    }

    testWidgets('role tokens read in the larks/robins dialect', (tester) async {
      final figure = await pumpHey(tester, Dialect.larksRobins);
      expect(find.text('larks'), findsWidgets);
      expect(find.text('robins'), findsWidgets);
      // The raw canonical token is what the facet used to show.
      expect(find.text('role1s'), findsNothing);

      await tester.tap(find.text('larks').last);
      await tester.pumpAndSettle();
      // Display-only: storage stays canonical, so the compiled filter matches
      // regardless of which dialect the searcher happens to be using.
      expect(figure.params['meetTarget'], 'role1s');
    });

    testWidgets('the same tokens read in a gents/ladies dialect', (
      tester,
    ) async {
      // Gendered terms ship as a CUSTOM dialect, not a preset, so build one —
      // which also exercises the custom-dialect path rather than only presets.
      final gentsLadies = Dialect(
        name: 'Gents/Ladies',
        roles: const {
          'role1': RoleTerm('gent'),
          'role2': RoleTerm('lady', plural: 'ladies'),
        },
      );
      final figure = await pumpHey(tester, gentsLadies);
      expect(find.text('gents'), findsWidgets);
      expect(find.text('ladies'), findsWidgets);
      // The crux of the bug: two callers with different role terminology were
      // both shown `role1s`. Neither sees the other's word now.
      expect(find.text('larks'), findsNothing);
      expect(find.text('role1s'), findsNothing);

      await tester.tap(find.text('gents').last);
      await tester.pumpAndSettle();
      expect(figure.params['meetTarget'], 'role1s');
    });

    testWidgets('non-role dancer tokens are humanized, not left raw', (
      tester,
    ) async {
      await pumpHey(tester, Dialect.larksRobins);
      // Deliberately a MULTI-WORD token. `neighbors` would be a vacuous choice:
      // it humanizes to itself, so the assertion would pass against the old
      // `Text(choice)` too and could never fail.
      expect(find.text('prevNeighbors'), findsNothing);
      expect(find.text('prev neighbors'), findsWidgets);
    });

    testWidgets('the "Any" option names the param in human terms', (
      tester,
    ) async {
      await pumpHey(tester, Dialect.larksRobins);
      // "Any meetTarget" leaked an internal identifier into the UI.
      expect(find.text('Any meetTarget'), findsNothing);
      expect(find.text('Any meet target'), findsWidgets);
    });

    testWidgets('structural vocabulary is humanized too', (tester) async {
      // `direction` is not dialect vocabulary, so it takes the humanizer
      // branch — the same one the dance editor uses for these tokens.
      final figure = BuilderFigure(move: 'slide');
      await _pump(
        tester,
        root: BuilderGroup(
          children: [BuilderThen(before: figure, after: BuilderFigure())],
        ),
        taxonomy: Taxonomy(
          version: 1,
          form: DanceForm.contra,
          moves: [
            MoveDef(
              id: 'slide',
              displayName: 'Slide',
              renderTemplate: '{move} {dir}',
              params: {
                'dir': ParamSpec(
                  ParamKind.direction,
                  defaultValue: 'along',
                  choices: const ['along', 'rightDiagonal'],
                ),
              },
            ),
          ],
        ),
      );
      await tester.tap(find.byKey(ValueKey('param-${figure.id}-dir')));
      await tester.pumpAndSettle();
      expect(find.text('rightDiagonal'), findsNothing);
      expect(find.text('right diagonal'), findsWidgets);
    });
  });
}
