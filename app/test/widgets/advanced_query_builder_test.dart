import 'package:compendium_app/src/search/collection_query.dart';
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
  const _Host({required this.root, required this.sectionLabels});
  final BuilderGroup root;
  final List<String> sectionLabels;

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
            taxonomy: contraTaxonomy,
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
}) async {
  await setScreenSize(tester, screenSize);
  await tester.pumpWidget(_Host(root: root, sectionLabels: sectionLabels));
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
}
