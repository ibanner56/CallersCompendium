import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/decimal_turns_scope.dart';
import 'package:compendium_app/src/data/verbose_figure_rendering_scope.dart';
import 'package:compendium_app/src/screens/glossary/glossary_screen.dart';

import '../support/l10n_harness.dart';

Future<ValueNotifier<Dialect>> _pump(
  WidgetTester tester, {
  Size size = const Size(500, 900),
  Dialect? dialect,
  List<FigureGlossaryEntry>? entries,
  bool decimals = false,
  bool verbose = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(dialect ?? Dialect.larksRobins);
  addTearDown(notifier.dispose);
  final decimalsNotifier = ValueNotifier<bool>(decimals);
  addTearDown(decimalsNotifier.dispose);
  final verboseNotifier = ValueNotifier<bool>(verbose);
  addTearDown(verboseNotifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      // Scopes wrap every route, as in main.dart, so pushed detail pages
      // see the dialect too.
      builder: (context, child) => ActiveDialectScope(
        notifier: notifier,
        child: DecimalTurnsScope(
          notifier: decimalsNotifier,
          child: VerboseFigureRenderingScope(
            notifier: verboseNotifier,
            child: child!,
          ),
        ),
      ),
      home: GlossaryScreen(entries: entries),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const ValueKey('glossary-search')), query);
  await tester.pumpAndSettle();
}

final _renderer = FigureRenderer(contraTaxonomy);

/// The shipped entries with one definition swapped in, so the rendering path
/// is exercised whatever the shipped definitions currently say.
List<FigureGlossaryEntry> _withChainDefinition() => figureGlossaryEntries(
  contraTaxonomy,
  definitions: const {
    'chain': FigureDefinition(
      definition: 'Role2s cross to the other side.',
      description: 'The role1s turn the role2s in.',
    ),
  },
);

void main() {
  testWidgets('lists the shipped figures, alphabetized by dialect name', (
    tester,
  ) async {
    await _pump(tester, size: const Size(500, 20000));
    final titles = [
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
        ((tile.title! as Text).data!),
    ];
    expect(titles, hasLength(figureGlossaryEntries(contraTaxonomy).length));
    final sorted = [...titles]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    expect(titles, sorted);
    // Named in the dialect: a role token in a figure name reads as a role term.
    for (final e in figureGlossaryEntries(contraTaxonomy)) {
      final name = _renderer.displayMoveName(e.id, Dialect.larksRobins);
      expect(titles.any((t) => t.startsWith(name)), isTrue, reason: name);
    }
    expect(titles, isNot(contains('custom')));
  });

  testWidgets('search matches names and legacy keywords, and says when '
      'nothing matches', (tester) async {
    await _pump(tester);

    await _search(tester, 'gypsy');
    expect(
      find.byKey(const ValueKey('glossary-entry-shoulder_round')),
      findsOneWidget,
    );
    expect(find.byType(ListTile), findsOneWidget);

    await _search(tester, 'zzz-no-such-figure');
    expect(find.byKey(const ValueKey('glossary-no-matches')), findsOneWidget);
    expect(find.text('No figures match “zzz-no-such-figure”.'), findsOneWidget);
  });

  testWidgets('a figure with no shipped definition says so', (tester) async {
    await _pump(
      tester,
      entries: figureGlossaryEntries(contraTaxonomy, definitions: const {}),
    );
    await _search(tester, 'shoulder round');
    await tester.tap(
      find.byKey(const ValueKey('glossary-entry-shoulder_round')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('glossary-no-definition')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('glossary-definition')), findsNothing);
  });

  testWidgets('definitions and examples follow the active dialect', (
    tester,
  ) async {
    final dialect = await _pump(tester, entries: _withChainDefinition());
    await _search(tester, 'chain');
    // The list subtitle is the definition, rendered in the dialect.
    expect(find.text('Robins cross to the other side.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('glossary-entry-chain')));
    await tester.pumpAndSettle();

    String text(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;
    expect(text('glossary-definition'), 'Robins cross to the other side.');
    expect(text('glossary-description'), 'The larks turn the robins in.');
    expect(
      text('glossary-example'),
      _renderer.render(Figure(move: 'chain'), Dialect.larksRobins),
    );

    dialect.value = Dialect.leadsFollows;
    await tester.pumpAndSettle();
    expect(text('glossary-definition'), 'Follows cross to the other side.');
    expect(text('glossary-description'), 'The leads turn the follows in.');
    expect(
      text('glossary-example'),
      _renderer.render(Figure(move: 'chain'), Dialect.leadsFollows),
    );
  });

  testWidgets('an alias names the figure it is a variant of', (tester) async {
    await _pump(tester);
    await _search(tester, 'seesaw');
    await tester.tap(find.byKey(const ValueKey('glossary-entry-see_saw')));
    await tester.pumpAndSettle();

    expect(find.text('A variant of dosido.'), findsOneWidget);
    // The alias pins `shoulder`, so it is not offered as a parameter.
    final params = tester
        .widget<Text>(find.byKey(const ValueKey('glossary-parameters')))
        .data!;
    expect(params.toLowerCase(), isNot(contains('shoulder')));
  });

  testWidgets('the base figure lists its aliases, and strikes through '
      'discouraged legacy names', (tester) async {
    await _pump(tester);
    await _search(tester, 'shoulder round');
    await tester.tap(
      find.byKey(const ValueKey('glossary-entry-shoulder_round')),
    );
    await tester.pumpAndSettle();

    final gypsy = tester.widget<Text>(find.text('gypsy'));
    expect(gypsy.style?.decoration, TextDecoration.lineThrough);
    expect(gypsy.semanticsLabel, 'Discouraged term: gypsy');
    final gyre = tester.widget<Text>(find.text('gyre'));
    expect(gyre.style?.decoration, TextDecoration.lineThrough);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _search(tester, 'dosido');
    await tester.tap(find.byKey(const ValueKey('glossary-entry-do_si_do')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('glossary-also-known-as')),
        matching: find.text('seesaw'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the wide layout shows the detail beside the list', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1200, 900));
    expect(
      find.byKey(const ValueKey('glossary-select-prompt')),
      findsOneWidget,
    );

    await _search(tester, 'shoulder round');
    await tester.tap(
      find.byKey(const ValueKey('glossary-entry-shoulder_round')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsNothing, reason: 'not a pushed route');
    expect(find.byKey(const ValueKey('glossary-detail')), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const ValueKey('glossary-entry-shoulder_round')),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets('no two rows read the same: a same-named variant is qualified '
      'by what it fixes', (tester) async {
    await _pump(tester, size: const Size(500, 20000));
    final titles = [
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
        ((tile.title! as Text).data!),
    ];
    expect(titles.toSet().length, titles.length, reason: '$titles');
    expect(titles, containsAll(['pull by', 'pull by (neighbors)']));
  });

  testWidgets('the example follows Decimal turns and always-verbose, and is '
      'spoken in full', (tester) async {
    final figure = Figure(move: 'star_promenade');
    final terse = _renderer.render(figure, Dialect.larksRobins);
    final decimal = _renderer.render(
      figure,
      Dialect.larksRobins,
      decimals: true,
    );
    final spoken = _renderer.renderVerbose(figure, Dialect.larksRobins);
    expect(decimal, isNot(terse), reason: 'fixture must show a fraction');

    Future<Text> exampleWith({
      bool decimals = false,
      bool verbose = false,
    }) async {
      // A fresh tree, so the previous run's pushed detail page is gone.
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, decimals: decimals, verbose: verbose);
      await _search(tester, 'star promenade');
      await tester.tap(
        find.byKey(const ValueKey('glossary-entry-star_promenade')),
      );
      await tester.pumpAndSettle();
      return tester.widget<Text>(
        find.byKey(const ValueKey('glossary-example')),
      );
    }

    var example = await exampleWith();
    expect(example.data, terse);
    expect(example.semanticsLabel, spoken);
    example = await exampleWith(decimals: true);
    expect(example.data, decimal);
    example = await exampleWith(verbose: true);
    expect(example.data, spoken);
  });

  testWidgets('a custom dialect that renames a figure still shows its '
      'canonical name', (tester) async {
    final custom = Dialect(
      name: 'Custom',
      moves: const {'allemande': 'hand turn'},
    );
    await _pump(tester, dialect: custom);
    await _search(tester, 'hand turn');
    await tester.tap(find.byKey(const ValueKey('glossary-entry-allemande')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('glossary-also-known-as')),
        matching: find.text('allemande'),
      ),
      findsOneWidget,
    );
  });
}
